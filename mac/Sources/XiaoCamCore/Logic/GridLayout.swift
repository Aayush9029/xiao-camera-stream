public struct GridLayout: Equatable, Sendable {
    public let count: Int
    public let columns: Int
    public let rows: Int

    public init(count: Int, columns requestedColumns: Int? = nil) {
        let count = max(count, 1)
        let columns: Int
        if let requestedColumns {
            columns = min(max(requestedColumns, 1), count)
        } else {
            var square = 1
            while square * square < count { square += 1 }
            columns = square
        }
        self.count = count
        self.columns = columns
        self.rows = (count + columns - 1) / columns
    }

    public func position(of index: Int) -> (row: Int, column: Int) {
        (index / columns, index % columns)
    }
}
