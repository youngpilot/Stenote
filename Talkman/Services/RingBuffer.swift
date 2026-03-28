import Foundation

struct RingBuffer<T>: @unchecked Sendable where T: Sendable {
    private var storage: [T]
    private var writeIndex = 0
    private(set) var count = 0
    let capacity: Int

    init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        self.storage = Array(repeating: defaultValue, count: capacity)
    }

    mutating func append(_ element: T) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    mutating func append(contentsOf elements: [T]) {
        for element in elements {
            append(element)
        }
    }

    func toArray() -> [T] {
        if count < capacity {
            return Array(storage[0..<count])
        }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }
}
