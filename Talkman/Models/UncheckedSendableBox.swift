/// Wraps a non-Sendable value, asserting that access is safe.
/// Only use when you can guarantee single-writer access (e.g., all access from @MainActor).
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
