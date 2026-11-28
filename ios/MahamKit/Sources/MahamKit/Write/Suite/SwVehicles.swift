import Foundation

/// The port of the company's vehicles (src/db/vehicles.ts): a plate no
/// other vehicle has, the company's driver and fixed asset, the papers
/// given the new plate; refused in a cloud without the records of version 16.
public enum SwVehicles {
  /// `createVehicle(companyId, overrides)`: a new vehicle for the form.
  public static func newVehicle(
    companyId: String, id: String = newId(), stamp: String = Defaults.nowStamp(), _ overrides: [String: JSONValue] = [:]
  ) -> JSONValue {
    var fields: [String: JSONValue] = [
      "id": .string(id), "companyId": .string(companyId), "plate": "", "make": "", "model": "", "year": .null,
      "chassisNumber": "", "assetId": .null, "driverEmployeeId": .null, "notes": "", "archived": false,
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    for (key, value) in overrides { fields[key] = value }
    return .object(fields)
  }

  /// `assertCloudHasVehicles`.
  static func assertCloudHasVehicles(_ cloud: SwCloud?) throws {
    if !SwCloud.allows(cloud, "tables_v16") {
      throw WriteFailure(
        "The cloud needs the latest database script first. Ask the owner of the company to run it.")
    }
  }

  /// The year as `new Date().getFullYear()` gives it, on this device's calendar.
  static func year(_ ctx: WriteContext) -> Int {
    Int(ctx.today.prefix(4)) ?? 0
  }

  /// `saveVehicle(input)`: saves a vehicle; its papers get the new plate when it changes.
  @discardableResult
  public static func save(_ ctx: WriteContext, _ input: JSONValue, cloud: SwCloud?) throws -> JSONValue {
    let fields = SwField.fields(input)
    guard let company = ctx.get("companies", SwField.text(fields, "companyId"))?.object else {
      throw WriteFailure("Company not found")
    }
    let companyId = company["id"] ?? .null
    try assertCloudHasVehicles(cloud)
    let plate = SwText.tidy(fields["plate"]?.string)
    if plate.isEmpty { throw WriteFailure("Enter the vehicle’s plate number.") }
    let key = SwText.plateKey(plate)
    let twin = ctx.all("vehicles").first { other in
      other["companyId"] == companyId && other["id"] != fields["id"]
        && SwText.plateKey(other["plate"]?.string ?? "") == key
    }
    if twin != nil { throw WriteFailure("Vehicle {plate} is already on the list.", ["plate": plate]) }
    let given = WebJS.truthy(fields["year"]) ? WebJS.toNumber(fields["year"]) : 0
    let year: Double? = given == 0 ? nil : (given < 0 ? -((-given).rounded(.down)) : given.rounded(.down))
    if let year, year < 1950 || year > Double(self.year(ctx) + 1) {
      throw WriteFailure("Enter the year it was made, for example 2022.")
    }
    if let driverId = SwField.id(fields["driverEmployeeId"]) {
      guard let driver = ctx.get("employees", driverId)?.object, driver["companyId"] == companyId else {
        throw WriteFailure("Choose the driver from the company’s employees.")
      }
    }
    if let assetId = SwField.id(fields["assetId"]) {
      guard let asset = ctx.get("assets", assetId)?.object, asset["companyId"] == companyId else {
        throw WriteFailure("Choose one of the company’s fixed assets.")
      }
    }
    let id = SwField.text(fields, "id")
    let existing = ctx.get("vehicles", id)?.object
    var vehicle = fields
    vehicle["plate"] = .string(plate)
    vehicle["make"] = .string(SwText.tidy(fields["make"]?.string))
    vehicle["model"] = .string(SwText.tidy(fields["model"]?.string))
    vehicle["year"] = year.map { JSONValue.number($0) } ?? .null
    vehicle["chassisNumber"] = .string(SwText.tidy(fields["chassisNumber"]?.string).uppercased())
    vehicle["assetId"] = SwField.string(SwField.id(fields["assetId"]))
    vehicle["driverEmployeeId"] = SwField.string(SwField.id(fields["driverEmployeeId"]))
    vehicle["notes"] = .string(SwText.trim(fields["notes"]?.string))
    vehicle["updatedAt"] = .string(ctx.stamp)
    if existing == nil { vehicle["createdAt"] = vehicle["updatedAt"] }
    ctx.put("vehicles", .object(vehicle))
    if let existing, existing["plate"] != .string(plate) {
      // Older versions show the plate kept on each paper.
      for paper in ctx.all("complianceDocuments") where paper["vehicleId"] == .string(id) {
        var renamed = SwField.fields(paper)
        renamed["ownerName"] = .string(plate)
        renamed["updatedAt"] = vehicle["updatedAt"]
        ctx.put("complianceDocuments", .object(renamed))
      }
    }
    ctx.logActivity(
      entity: "compliance", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(existing != nil ? "Vehicle {plate} updated" : "Vehicle {plate} added", vars: ["plate": plate]))
    return .object(vehicle)
  }

  /// `setVehicleArchived(id, archived)`: stops (or resumes) listing a vehicle; its papers stay.
  public static func setArchived(_ ctx: WriteContext, id: String, archived: Bool, cloud: SwCloud?) throws {
    guard var vehicle = ctx.get("vehicles", id)?.object else { return }
    try assertCloudHasVehicles(cloud)
    vehicle["archived"] = .bool(archived)
    vehicle["updatedAt"] = .string(ctx.stamp)
    ctx.put("vehicles", .object(vehicle))
    ctx.logActivity(
      entity: "compliance", entityId: id, action: archived ? "archived" : "restored",
      message: ActivityMessage(
        archived ? "Vehicle {plate} archived" : "Vehicle {plate} restored",
        vars: ["plate": SwField.text(vehicle, "plate")]))
  }

  /// `deleteVehicle(id)`: deletes a vehicle added by mistake; one with papers is archived instead.
  public static func delete(_ ctx: WriteContext, id: String, cloud: SwCloud?) throws {
    guard let vehicle = ctx.get("vehicles", id)?.object else { return }
    try assertCloudHasVehicles(cloud)
    if ctx.all("complianceDocuments").contains(where: { $0["vehicleId"] == .string(id) }) {
      throw WriteFailure("This vehicle has papers in the register. Archive it instead.")
    }
    ctx.delete("vehicles", id)
    ctx.logActivity(
      entity: "compliance", entityId: id, action: "deleted",
      message: ActivityMessage("Vehicle {plate} deleted", vars: ["plate": SwField.text(vehicle, "plate")]))
  }

  /// Vehicle papers with the same plate or name, not linked to a vehicle yet (`UnlinkedVehicle`).
  public struct Unlinked: Sendable {
    /// The plate or name as the papers have it.
    public let name: String
    public var documents: [JSONValue]
    /// The vehicle with that plate, when there is one; nil adds one.
    public let vehicle: JSONValue?
  }

  /// `unlinkedVehicles(documents, vehicles)`: the register's vehicle papers
  /// that name a vehicle only by its plate, grouped by it.
  public static func unlinked(documents: [JSONValue], vehicles: [JSONValue]) -> [Unlinked] {
    var byPlate: [String: JSONValue] = [:]
    for vehicle in vehicles { byPlate[SwText.plateKey(vehicle["plate"]?.string ?? "")] = vehicle }
    var order: [String] = []
    var groups: [String: Unlinked] = [:]
    let oldestFirst = documents.enumerated().sorted { a, b in
      let (ca, cb) = (a.element["createdAt"]?.string ?? "", b.element["createdAt"]?.string ?? "")
      if ca != cb { return WebJS.less(ca, cb) }
      return a.offset < b.offset
    }.map(\.element)
    for doc in oldestFirst {
      let ownerName = doc["ownerName"]?.string ?? ""
      if doc["ownerType"] != .string("vehicle") || WebJS.truthy(doc["vehicleId"]) || SwText.trim(ownerName).isEmpty {
        continue
      }
      let key = SwText.plateKey(ownerName)
      if key.isEmpty { continue }
      if groups[key] == nil {
        order.append(key)
        groups[key] = Unlinked(name: SwText.tidy(ownerName), documents: [], vehicle: byPlate[key])
      }
      groups[key]?.documents.append(doc)
    }
    return order.compactMap { groups[$0] }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }

  /// `linkVehiclePapers(companyId)`: links each vehicle paper to its vehicle
  /// by its plate, adding a vehicle for each plate not on the list yet.
  @discardableResult
  public static func linkPapers(_ ctx: WriteContext, cloud: SwCloud?) throws -> (vehicles: Int, papers: Int) {
    try assertCloudHasVehicles(cloud)
    let company = JSONValue.string(ctx.companyId)
    let documents = ctx.all("complianceDocuments").filter { $0["companyId"] == company }
    let vehicles = ctx.all("vehicles").filter { $0["companyId"] == company }
    var added = 0
    var papers = 0
    let stamp = ctx.stamp
    for group in unlinked(documents: documents, vehicles: vehicles) {
      var vehicleId = group.vehicle?["id"]?.string ?? ""
      if group.vehicle == nil {
        let vehicle = newVehicle(
          companyId: ctx.companyId, id: ctx.newId(), stamp: stamp, ["plate": .string(group.name)])
        ctx.put("vehicles", vehicle)
        vehicleId = vehicle["id"]?.string ?? ""
        ctx.logActivity(
          entity: "compliance", entityId: vehicleId, action: "created",
          message: ActivityMessage("Vehicle {plate} added", vars: ["plate": group.name]))
        added += 1
      }
      for doc in group.documents {
        var linked = SwField.fields(doc)
        linked["vehicleId"] = .string(vehicleId)
        linked["updatedAt"] = .string(stamp)
        ctx.put("complianceDocuments", .object(linked))
      }
      papers += group.documents.count
    }
    return (added, papers)
  }
}
