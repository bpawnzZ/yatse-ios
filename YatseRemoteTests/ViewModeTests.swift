import XCTest
@testable import YatseRemote

/// Guards the one layout setting every browse screen reads.
///
/// The rendered layouts cannot be seen in CI, so what is checked here is what the
/// screens have to agree on: how many columns each mode means, that the
/// two-column grid is what a fresh install opens with, and that a mode survives
/// being stored and read back. It replaced the tests for the two rules that used
/// to decide the layout — the media kind and the path — which are gone.
///
/// The guard that each mode's SF Symbol resolves lives with the other symbol
/// checks in `ShellNavigationTests`, which owns that helper.
final class ViewModeTests: XCTestCase {

    /// Two columns is the requested default, so it is asserted rather than
    /// assumed — it is what a fresh install opens as.
    func testTheDefaultIsTheTwoColumnGrid() {
        XCTAssertEqual(ViewMode.fallback, .grid)
        XCTAssertEqual(ViewMode.fallback.columnCount, 2)
    }

    func testEachModeCarriesItsColumnCount() {
        XCTAssertEqual(ViewMode.grid.columnCount, 2)
        XCTAssertEqual(ViewMode.compact.columnCount, 3)
        XCTAssertEqual(ViewMode.dense.columnCount, 4)
        XCTAssertEqual(ViewMode.list.columnCount, 1)
    }

    /// Every grid branch renders `gridColumns`, so the count it hands `LazyVGrid`
    /// has to be the count the mode claims.
    func testGridColumnsMatchTheColumnCount() {
        for mode in ViewMode.allCases {
            XCTAssertEqual(mode.gridColumns.count, mode.columnCount, "\(mode.rawValue)")
        }
    }

    func testOnlyTheListIsNotAGrid() {
        XCTAssertTrue(ViewMode.grid.isGrid)
        XCTAssertTrue(ViewMode.compact.isGrid)
        XCTAssertTrue(ViewMode.dense.isGrid)
        XCTAssertFalse(ViewMode.list.isGrid)
    }

    /// A mode that does not read back from its stored form is a layout that
    /// silently resets on every launch.
    func testEveryModeSurvivesBeingStored() {
        for mode in ViewMode.allCases {
            XCTAssertEqual(ViewMode(rawValue: mode.rawValue), mode, "\(mode.rawValue)")
        }
        XCTAssertNil(ViewMode(rawValue: "two-wide"), "an unknown stored value must not resolve")
    }

    /// The control writes the raw value under `ViewMode.storageKey` and the screens
    /// read that same key; this is that contract, over the real defaults store.
    func testTheStoredValueResolvesToTheModeThatWasChosen() {
        let key = ViewMode.storageKey
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set(ViewMode.dense.rawValue, forKey: key)

        let stored = UserDefaults.standard.string(forKey: key)
        XCTAssertEqual(stored.flatMap(ViewMode.init(rawValue:)), .dense)
    }

    /// The denser the grid, the smaller the text has to be: at four columns there
    /// is no room for the two-line detail the two-column grid shows.
    func testDensityDrivesTheTileText() {
        XCTAssertFalse(ViewMode.grid.usesSmallTileText)
        XCTAssertTrue(ViewMode.compact.usesSmallTileText)
        XCTAssertTrue(ViewMode.dense.usesSmallTileText)

        XCTAssertTrue(ViewMode.grid.showsTileDetail)
        XCTAssertTrue(ViewMode.compact.showsTileDetail)
        XCTAssertFalse(ViewMode.dense.showsTileDetail)
    }

    /// Four layouts, each offered under its own name — a duplicate title would be
    /// two menu rows that look identical.
    func testEveryModeIsOfferedOnce() {
        XCTAssertEqual(ViewMode.allCases.count, 4)
        XCTAssertEqual(Set(ViewMode.allCases.map(\.title)).count, 4)
    }
}
