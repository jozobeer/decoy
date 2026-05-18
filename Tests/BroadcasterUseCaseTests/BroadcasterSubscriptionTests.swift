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
@testable import BroadcasterUseCase

/// Spec for `BroadcasterUseCase.subscribeEvents()`. Returns a passive
/// `BroadcasterEvents` value facade wrapping an `AsyncStream<BroadcasterEvent>`.
/// Mirrors `RecorderSubscriptionTests` — Domain holds no lifecycle
/// behavior, so callers must invoke `events.cancel()` explicitly
/// (typically via `defer { Task { await events.cancel() } }`) to release
/// the actor-side subscriber slot.
@Suite("BroadcasterSubscription", .timeLimit(.minutes(1)))
struct BroadcasterSubscriptionTests {

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Iteration

    @Test func subscription_isIterable() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "iterate"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            let events = await broadcaster.subscribeEvents()
            var observed: [BroadcasterEvent] = []
            for await event in events {
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

    // MARK: - Explicit cleanup contract

    @Test func subscription_explicitCancel_releasesSubscriber() async throws {
        // Caller obtains `BroadcasterEvents` but never iterates. The
        // passive value facade has no deinit-driven cleanup, so callers
        // must invoke `events.cancel()` explicitly. Recommended pattern:
        // `defer { Task { await events.cancel() } }` around `for await`.
        let source = InMemoryCameraSource(emitting: [])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            let transient = await broadcaster.subscribeEvents()
            #expect(await broadcaster.subscriberCount == 1)
            await transient.cancel()
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await broadcaster.subscriberCount == 0)
            await broadcaster.shutdown()
        }
    }

    @Test func subscription_explicitCancel_isIdempotent() async throws {
        // `cancel()` may be invoked from multiple cleanup paths (a
        // `defer` after iteration plus a deinit chain on a wrapper, for
        // example). Calling it twice must not crash and must not
        // double-remove anything on the actor side.
        let source = InMemoryCameraSource(emitting: [])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            let events = await broadcaster.subscribeEvents()
            await events.cancel()
            await events.cancel()
            #expect(await broadcaster.subscriberCount == 0)
            await broadcaster.shutdown()
        }
    }

    @Test func subscription_iteratorCancellation_removesSubscriber() async throws {
        // Iterator-side cancellation goes through AsyncStream.onTermination
        // which schedules removeSubscriber on the actor — even when the
        // caller never invokes `events.cancel()` explicitly.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "iteratorCancel"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            let events = await broadcaster.subscribeEvents()
            #expect(await broadcaster.subscriberCount == 1)

            let consumer = Task<Void, Never> {
                for await _ in events {
                    // never break — only cancellation ends iteration
                }
            }
            consumer.cancel()
            _ = await consumer.value
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await broadcaster.subscriberCount == 0)
            await broadcaster.shutdown()
        }
    }

    @Test func multipleSubscriptions_independentCleanup() async throws {
        // Cancelling one subscriber must not affect the other.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingSink(error: TestError(label: "independent"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            let persistent = await broadcaster.subscribeEvents()
            let transient = await broadcaster.subscribeEvents()
            #expect(await broadcaster.subscriberCount == 2)

            await transient.cancel()
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await broadcaster.subscriberCount == 1)

            var observed = 0
            for await _ in persistent {
                observed += 1
                break
            }
            await broadcaster.shutdown()
            #expect(observed == 1)
        }
    }

    // MARK: - Shutdown race protection

    @Test func shutdown_blocksConcurrentHandle() async throws {
        // `shutdown()` sets a sticky `terminated` flag before its
        // `await`, so a concurrent `handle(.startDecoy)` resumed via
        // actor reentrancy must observe the flag and become a no-op.
        // Without this guard a new routing Task could spawn after
        // shutdown's cleanup runs and escape terminal cleanup.
        let source = InMemoryCameraSource(emitting: [])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            await broadcaster.shutdown()
            // Post-shutdown command must be ignored — state stays live.
            await broadcaster.handle(.startDecoy(.loop))
            #expect(await broadcaster.state == .live)
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
