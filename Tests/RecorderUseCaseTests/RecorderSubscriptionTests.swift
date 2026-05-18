import Testing
import Foundation
import ConcurrencyExtras
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
@testable import RecorderUseCase

/// Spec for `RecorderUseCase.subscribeEvents()`. Returns a
/// `RecorderEvents` AsyncSequence wrapping an `AsyncStream<RecorderEvent>`.
/// Cleanup of the actor-side subscriber slot is driven by the stream's
/// `onTermination` callback when the iterator drops or is cancelled
/// (the Phase 3a refactor dropped the prior `Subscription` token's
/// deinit-driven cleanup in favour of the simpler bare-AsyncStream
/// model that the lyra UseCase pattern uses).
@Suite("RecorderSubscription", .timeLimit(.minutes(1)))
struct RecorderSubscriptionTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, pixelData: Data(repeating: byte, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    @Test func subscription_isIterable() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let events = await recorder.subscribeEvents()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            var observed: [RecorderEvent] = []
            for await event in events {
                observed.append(event)
                break
            }
            #expect(observed.count == 1)
            guard case .saved = try #require(observed.first) else {
                Issue.record("expected .saved")
                return
            }
        }
    }

    @Test func subscription_iteratorCancellation_removesSubscriber() async {
        // Iterator cancellation fires the AsyncStream's onTermination
        // which removes the actor-side subscriber slot.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let events = await recorder.subscribeEvents()
            #expect(await recorder.subscriberCount == 1)

            let consumer = Task<Void, Never> {
                for await _ in events {
                    // never break — only cancellation ends iteration
                }
            }
            consumer.cancel()
            _ = await consumer.value
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await recorder.subscriberCount == 0)
        }
    }

    @Test func multipleSubscriptions_independentCleanup() async {
        // Two subscribers; cancelling one must not affect the other.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let persistent = await recorder.subscribeEvents()
            let transient = await recorder.subscribeEvents()
            #expect(await recorder.subscriberCount == 2)

            let doomed = Task<Void, Never> {
                for await _ in transient {}
            }
            doomed.cancel()
            _ = await doomed.value
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await recorder.subscriberCount == 1)

            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)
            var observed = 0
            for await _ in persistent {
                observed += 1
                break
            }
            #expect(observed == 1)
        }
    }

    @Test func subscription_explicitCancel_releasesSubscriber() async {
        // Caller obtains `RecorderEvents` but never iterates (the
        // observing Task was cancelled before entering `for await`).
        // The passive value facade has no deinit-driven cleanup, so
        // callers must invoke `events.cancel()` explicitly (typically
        // via `defer { Task { await events.cancel() } }`). This
        // covers the leak path that surfaces during `MenuBarViewModel.start()`'s
        // cancel→recreate cycle.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let transient = await recorder.subscribeEvents()
            #expect(await recorder.subscriberCount == 1)
            await transient.cancel()
            for _ in 0..<50 { await Task.megaYield() }
            #expect(await recorder.subscriberCount == 0)
        }
    }

    @Test func subscription_explicitCancel_isIdempotent() async {
        // `cancel()` may be invoked from multiple cleanup paths
        // (`defer` after `for await`, deinit chains in caller-side
        // wrappers). Calling it twice must not crash and must not
        // double-remove anything in the actor-side bookkeeping.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let events = await recorder.subscribeEvents()
            await events.cancel()
            await events.cancel()
            #expect(await recorder.subscriberCount == 0)
        }
    }

    @Test func shutdown_blocksConcurrentHandle() async {
        // `shutdown()` sets a sticky `terminated` flag before its
        // `await`, so a concurrent `handle(.startRecording)` that
        // resumes via actor reentrancy must observe the flag and
        // become a no-op. Otherwise a new consumption Task spawns
        // after the shutdown await and escapes terminal cleanup.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.shutdown()
            // Post-shutdown command must be ignored — state stays idle.
            await recorder.handle(.startRecording)
            #expect(await recorder.state == .idle)
        }
    }

    @Test func shutdown_terminatesAllSubscribers() async {
        // shutdown() finishes every continuation and clears the dict.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let a = await recorder.subscribeEvents()
            let b = await recorder.subscribeEvents()
            #expect(await recorder.subscriberCount == 2)

            let aTask = Task<Int, Never> {
                var count = 0
                for await _ in a { count += 1 }
                return count
            }
            let bTask = Task<Int, Never> {
                var count = 0
                for await _ in b { count += 1 }
                return count
            }
            await recorder.shutdown()
            _ = await aTask.value
            _ = await bTask.value
            #expect(await recorder.subscriberCount == 0)
        }
    }
}
