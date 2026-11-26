#if DEBUG
  import MahamKit

  extension PreviewRecords {
    /// Each area's made-up records (purchases, items, accounting, people, …),
    /// merged by `PreviewRecords.all`.
    static var areaMakers: [(Company) -> [String: [JSONValue]]] {
      [inventoryArea(company:), contactsArea(company:), suiteArea(company:), accountingArea(company:), peopleArea(company:)]
    }
  }
#endif
