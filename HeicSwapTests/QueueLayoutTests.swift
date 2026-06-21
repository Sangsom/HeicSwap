//
//  QueueLayoutTests.swift
//  HeicSwapTests
//
//  The Convert queue's bounded-preview math (task 5.1): how many thumbnails render vs. how many
//  fold into the "+N" overflow tile, and how expanding changes that.
//

import Testing
@testable import HeicSwap

struct QueueLayoutTests {

    @Suite("Within the preview cap — everything shows")
    struct WithinCap {

        @Test("Counts at or under the cap show all items with no overflow", arguments: [
            (0, 8), (1, 8), (5, 8), (8, 8),
        ])
        func allVisible(total: Int, cap: Int) {
            let split = QueueLayout.split(total: total, cap: cap, isExpanded: false)
            #expect(split.visible == total)
            #expect(split.overflow == 0)
        }
    }

    @Suite("Over the cap — the last cell becomes +N")
    struct OverCap {

        @Test("One past the cap reserves the last cell for overflow")
        func justOverTheCap() {
            let split = QueueLayout.split(total: 9, cap: 8, isExpanded: false)
            #expect(split.visible == 7)
            #expect(split.overflow == 2)
        }

        @Test("Design spec mock: 12 items in a 4-cell preview → 3 thumbnails + “+9”")
        func designMock() {
            let split = QueueLayout.split(total: 12, cap: 4, isExpanded: false)
            #expect(split.visible == 3)
            #expect(split.overflow == 9)
        }

        @Test("Reserves exactly one cell for +N and conserves the total", arguments: [
            (9, 8), (12, 8), (100, 8), (13, 4),
        ])
        func reservesOneCellAndConserves(total: Int, cap: Int) {
            let split = QueueLayout.split(total: total, cap: cap, isExpanded: false)
            #expect(split.visible == cap - 1)
            #expect(split.visible + split.overflow == total)
        }
    }

    @Suite("Expanded — everything shows regardless of cap")
    struct Expanded {

        @Test("Expanding shows every item with no overflow", arguments: [
            (12, 8), (100, 8), (3, 4),
        ])
        func expandedShowsAll(total: Int, cap: Int) {
            let split = QueueLayout.split(total: total, cap: cap, isExpanded: true)
            #expect(split.visible == total)
            #expect(split.overflow == 0)
        }
    }
}
