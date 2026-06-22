//
//  TempWorkspaceTests.swift
//  HeicSwapTests
//
//  Covers the deterministic temp-file purge that backs task 10.3's cleanup (AC2). The suite is
//  serialized because it writes to and wipes the app's shared temp roots; no other suite touches
//  them, so serializing within this suite is enough to keep the assertions deterministic.
//

import Foundation
import Testing
@testable import HeicSwap

@Suite("TempWorkspace", .serialized)
struct TempWorkspaceTests {

    private let fileManager = FileManager.default

    /// Writes a one-byte file inside a fresh per-run subdirectory of `root` and returns its URL,
    /// mirroring how the engine / PDF builder / import service lay files out (root/<uuid>/<name>).
    private func seedFile(named name: String, under root: URL) throws -> URL {
        let runDirectory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let url = runDirectory.appending(path: name)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("Every working root sits under the single app temp root")
    func rootsAreNested() {
        let rootPath = TempWorkspace.root.path(percentEncoded: false)
        #expect(TempWorkspace.importsRoot.path(percentEncoded: false).hasPrefix(rootPath))
        #expect(TempWorkspace.conversionOutputsRoot.path(percentEncoded: false).hasPrefix(rootPath))
        #expect(TempWorkspace.pdfOutputsRoot.path(percentEncoded: false).hasPrefix(rootPath))
        // The three roots are distinct so outputs and imports can be purged independently.
        #expect(TempWorkspace.importsRoot != TempWorkspace.conversionOutputsRoot)
        #expect(TempWorkspace.conversionOutputsRoot != TempWorkspace.pdfOutputsRoot)
    }

    @Test("purgeOutputs removes conversion + PDF outputs but keeps imports")
    func purgeOutputsKeepsImports() throws {
        TempWorkspace.purgeAll()
        let conversion = try seedFile(named: "a.jpg", under: TempWorkspace.conversionOutputsRoot)
        let pdf = try seedFile(named: "a.pdf", under: TempWorkspace.pdfOutputsRoot)
        let imported = try seedFile(named: "o.heic", under: TempWorkspace.importsRoot)

        TempWorkspace.purgeOutputs()

        #expect(!exists(conversion))
        #expect(!exists(pdf))
        #expect(exists(imported)) // imports back the live queue — never dropped by an output purge

        TempWorkspace.purgeAll()
    }

    @Test("purgeImports removes imports but keeps outputs")
    func purgeImportsKeepsOutputs() throws {
        TempWorkspace.purgeAll()
        let imported = try seedFile(named: "o.heic", under: TempWorkspace.importsRoot)
        let conversion = try seedFile(named: "a.jpg", under: TempWorkspace.conversionOutputsRoot)

        TempWorkspace.purgeImports()

        #expect(!exists(imported))
        #expect(exists(conversion))

        TempWorkspace.purgeAll()
    }

    @Test("purgeAll removes the entire workspace")
    func purgeAllRemovesEverything() throws {
        let imported = try seedFile(named: "o.heic", under: TempWorkspace.importsRoot)
        let conversion = try seedFile(named: "a.jpg", under: TempWorkspace.conversionOutputsRoot)
        let pdf = try seedFile(named: "a.pdf", under: TempWorkspace.pdfOutputsRoot)

        TempWorkspace.purgeAll()

        #expect(!exists(imported))
        #expect(!exists(conversion))
        #expect(!exists(pdf))
        #expect(!exists(TempWorkspace.root))
    }

    @Test("removeTree removes only the named run directory")
    func removeTreeIsScoped() throws {
        TempWorkspace.purgeAll()
        let doomed = try seedFile(named: "a.jpg", under: TempWorkspace.conversionOutputsRoot)
        let kept = try seedFile(named: "b.jpg", under: TempWorkspace.conversionOutputsRoot)

        TempWorkspace.removeTree(at: doomed.deletingLastPathComponent())

        #expect(!exists(doomed))
        #expect(exists(kept)) // a sibling run's outputs survive a single-run purge

        TempWorkspace.purgeAll()
    }

    @Test("Purging a never-created workspace is a no-op, not a failure")
    func purgeMissingIsSafe() {
        TempWorkspace.purgeAll()
        TempWorkspace.purgeAll() // second call: nothing to remove, must not throw or trap
        #expect(!exists(TempWorkspace.root))
    }
}
