//
//  NetworkEgressTests.swift
//  HeicSwapTests
//
//  Locks the product's core promise — "your images never leave the device" — into executable
//  code (task 10.4). A custom `URLProtocol` observes every request the URL Loading System routes
//  through `URLSession.shared` / default-configured sessions, so a full conversion run (transcode
//  + resize + strip + image→PDF) can be asserted to make *zero* outbound requests. A regression
//  that quietly added an upload would surface here as a failing test on every PR, instead of as a
//  broken privacy guarantee in production.
//
//  Scope: `URLProtocol` observes the URL Loading System — the path any accidental `URLSession` /
//  `NSURLConnection` call would take. It does not see raw BSD sockets or `Network.framework`, but
//  the convert pipeline is ImageIO/CoreGraphics-only and opens neither, so the URL-loading layer
//  is exactly where a regression would land. The positive-control test below proves the monitor
//  actually fires, so this is not a silent no-op. Analytics (TelemetryDeck) is out of scope per
//  the task and is never exercised on the convert path.
//

import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import HeicSwap

// MARK: - Network egress monitor

/// A `URLProtocol` that records every request routed through the URL Loading System while it is
/// installed and fails each one immediately, so nothing actually leaves the device even if a
/// request were made. `nonisolated` because `URLProtocol` callbacks arrive on arbitrary threads;
/// the recording is guarded by a `Mutex`.
private nonisolated final class NetworkEgressMonitor: URLProtocol {

    private static let captured = Mutex<[URLRequest]>([])

    /// Begins observing: clears any prior recording and registers the protocol globally — which
    /// covers `URLSession.shared` and `URLSessionConfiguration.default` sessions, the path an
    /// accidental upload in the convert pipeline would take.
    static func install() {
        captured.withLock { $0.removeAll() }
        URLProtocol.registerClass(NetworkEgressMonitor.self)
    }

    /// Stops observing. Safe to call more than once.
    static func uninstall() {
        URLProtocol.unregisterClass(NetworkEgressMonitor.self)
    }

    /// Every request observed since the last `install()`.
    static var capturedRequests: [URLRequest] {
        captured.withLock { $0 }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        captured.withLock { $0.append(request) }
        return true // take over the request so it never reaches the network
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Already recorded in `canInit`; refuse to load so not a single byte egresses.
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

// MARK: - Tests

// Serialized: the monitor registers a global `URLProtocol` and shares one recording buffer, so the
// two tests must not overlap. No other suite performs networking (RevenueCat/TelemetryDeck are
// keyless and never touched on the convert path), so the brief install windows stay clean.
@Suite("Network egress (privacy guarantee)", .serialized)
struct NetworkEgressTests {

    /// A throwaway working directory removed on deinit.
    private final class Workspace {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "NetworkEgressTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    /// Writes a solid-color sRGB PNG, large enough that the resize and target-size paths do real
    /// work rather than short-circuiting.
    private func makeSourceImage(width: Int = 1200, height: Int = 900, in directory: URL) throws -> URL {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let url = directory.appending(path: "src-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test("AC1: a full conversion run (transcode · resize · strip · PDF) makes zero network requests")
    func conversionMakesZeroNetworkRequests() async throws {
        let workspace = try Workspace()
        let sources = [
            try makeSourceImage(in: workspace.root),
            try makeSourceImage(in: workspace.root),
        ]

        NetworkEgressMonitor.install()
        defer { NetworkEgressMonitor.uninstall() }

        let engine = ConversionEngine(outputDirectory: workspace.root.appending(path: "out"))

        // Transcode + resize + strip, all on the batch path.
        let outcomes = await engine.convertBatch(
            sources,
            with: ConversionOptions(
                format: .jpg, resizeMode: .maxDimension(pixels: 512), stripsMetadata: true
            )
        )
        // Target-size compression path (binary-search over quality).
        _ = try await engine.convert(
            sources[0],
            with: ConversionOptions(
                format: .jpg, resizeMode: .targetBytes(40_000), stripsMetadata: true
            )
        )
        // Image → multi-page PDF path.
        let pdfBuilder = PDFBuilder(outputDirectory: workspace.root.appending(path: "pdf"))
        _ = try await pdfBuilder.buildPDF(from: sources)

        // Sanity: the work actually ran, so "zero requests" reflects a real conversion, not a no-op.
        #expect(outcomes.count == sources.count)
        #expect(outcomes.allSatisfy { $0.didSucceed })

        let captured = NetworkEgressMonitor.capturedRequests
        #expect(
            captured.isEmpty,
            "Conversion must make no network requests; observed: \(captured.compactMap { $0.url?.absoluteString })"
        )
    }

    @Test("AC2: the monitor detects an injected network call (proves the guard is not a no-op)")
    func monitorDetectsInjectedNetworkCall() async throws {
        let endpoint = try #require(URL(string: "https://example.invalid/upload"))

        NetworkEgressMonitor.install()
        defer { NetworkEgressMonitor.uninstall() }

        // Stand-in for an upload accidentally added to the convert path. The monitor fails the
        // request so nothing egresses, but it must record that the attempt was made — that is what
        // makes AC1 meaningful: were such a call introduced into a conversion, AC1 would fail.
        _ = try? await URLSession.shared.data(from: endpoint)

        let captured = NetworkEgressMonitor.capturedRequests
        #expect(
            !captured.isEmpty,
            "Monitor must observe egress; otherwise AC1 could pass even if the convert path uploaded data"
        )
        #expect(captured.contains { $0.url == endpoint })
    }
}
