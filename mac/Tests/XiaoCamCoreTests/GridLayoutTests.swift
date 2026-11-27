import Testing
import XiaoCamCore

struct GridLayoutTests {
    @Test(arguments: [
        (1, 1, 1), (2, 2, 1), (3, 2, 2), (4, 2, 2), (5, 3, 2),
        (6, 3, 2), (7, 3, 3), (9, 3, 3), (10, 4, 3), (36, 6, 6),
    ])
    func picksANearSquareGrid(count: Int, columns: Int, rows: Int) {
        let layout = GridLayout(count: count)
        #expect(layout.columns == columns)
        #expect(layout.rows == rows)
        #expect(layout.columns * layout.rows >= count)
    }

    @Test func clampsRequestedColumns() {
        #expect(GridLayout(count: 5, columns: 9).columns == 5)
        #expect(GridLayout(count: 5, columns: 0).columns == 1)
        #expect(GridLayout(count: 7, columns: 2).rows == 4)
    }

    @Test func treatsZeroFramesAsOneCell() {
        let layout = GridLayout(count: 0)
        #expect(layout.count == 1)
        #expect(layout.columns == 1)
        #expect(layout.rows == 1)
    }

    @Test func placesCellsRowByRow() {
        let layout = GridLayout(count: 5)
        #expect(layout.position(of: 0) == (0, 0))
        #expect(layout.position(of: 2) == (0, 2))
        #expect(layout.position(of: 3) == (1, 0))
    }
}
