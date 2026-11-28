import Foundation

/// The kinds of record (the web's table names) this app may save. A kind
/// is listed here only once the ports of the web's write functions that
/// change it (MahamKit/Write) pass their parity tests against the web's own
/// outputs: a record saved on the iPhone must be what the web would have
/// saved, or the web's devices rewrite it. Until a kind is here, the pages
/// that would change it keep their New and Edit buttons hidden.
enum OneWritable {
  static let kinds: Set<String> = []
}
