import Testing
import Foundation
import Clocks
import ConcurrencyExtras
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
import InMemoryVirtualCameraSink
@testable import Broadcaster

/// Spec for the `Subscription`-token redesign of
/// `Broadcaster.subscribeEvents()`. Mirrors `RecorderSubscription` — the
/// previous `AsyncStream` return type left a cleanup gap when callers
/// abandoned the stream without iterating or broke out of `for-await`
/// normally. The token's `deinit` closes that gap by driving cleanup
/// deterministically.
@Suite("BroadcasterSubscription", .timeLimit(.minutes(1)))
struct BroadcasterSubscriptionTests {

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Subscription exposes events stream

    @Test func subscription_exposesEventsStream() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "expose"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let subscription = await broadcaster.subscribeEvents()
            var observed: [Broadcaster.Event] = []
            for await event in subscription.events {
                observed.append(event)
                break
            }
            await broadcaster.shutdown()
            #expect(observed.count == 1)
            guard case .sendFailed = try #require(observed.first) else {
                Issue.record("expected .sendFailed")
                return
            }
        }
    }

    // MARK: - Cleanup-on-drop (the gap fix)

    @Test func subscription_droppedWithoutIterating_removesSubscriber() async throws {
        let source = InMemoryCameraSource(emitting: [])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            do {
                let transient = await broadcaster.subscribeEvents()
                let mid = await broadcaster.subscriberCount
                #expect(mid == 1)
                // Reference transient after the await so ARC keeps it
                // alive through the count check (otherwise deinit races
                // the assertion).
                _ = transient.events
            }
            for _ in 0..<50 { await Task.megaYield() }
            let final = await broadcaster.subscriberCount
            #expect(final == 0)
            await broadcaster.shutdown()
        }
    }

    @Test func subscription_droppedAfterNormalBreak_removesSubscriber() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "normalBreak"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            do {
                let subscription = await broadcaster.subscribeEvents()
                for await _ in subscription.events { break }
                let mid = await broadcaster.subscriberCount
                #expect(mid == 1)
                _ = subscription.events
            }
            for _ in 0..<50 { await Task.megaYield() }
            let final = await broadcaster.subscriberCount
            #expect(final == 0)
            await broadcaster.shutdown()
        }
    }

    @Test func multipleSubscriptions_independentCleanup() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "independent"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let persistent = await broadcaster.subscribeEvents()
            do {
                let transient = await broadcaster.subscribeEvents()
                let mid = await broadcaster.subscriberCount
                #expect(mid == 2)
                _ = transient.events
            }
            for _ in 0..<50 { await Task.megaYield() }
            let after = await broadcaster.subscriberCount
            #expect(after == 1)
            var observed = 0
            for await _ in persistent.events {
                observed += 1
                break
            }
            await broadcaster.shutdown()
            #expect(observed == 1)
        }
    }
}

// MARK: - Test Doubles

private struct TestError: Error, Equatable, Sendable {
    let label: String
}

private actor FailingSink {
    private let error: any Error & Sendable

    init(error: any Error & Sendable) {
        self.error = error
    }
}

extension FailingSink: VirtualCameraSink {
    func send(_ frame: Frame) async throws {
        throw error
    }
}
