import Foundation

/// The port of the web's stock writes (src/db/inventory.ts), called by the
/// document ports when a document's stock changes. Being ported: until then
/// these do nothing, and documents with stock items stay unwritable
/// (`OneWritable`).
public enum InventoryWrites {
  /// `syncDocumentStock(companyId, documentId)`: the document's stock
  /// movements made to match it, and the products it touches costed again.
  public static func syncDocumentStock(_ ctx: WriteContext, documentId: String) throws {}

  /// `recost(company, productIds)`: the products' movements valued again in order.
  public static func recost(_ ctx: WriteContext, productIds: [String]) throws {}
}
