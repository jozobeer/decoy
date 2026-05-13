import Testing
import Foundation
import ConcurrencyExtras
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
@testable import Recorder

/// Spec for the `Subscription`-token redesign of `Recorder.subscribeEvents()`.
/// The previous design returned a bare `AsyncStream<Event>` and relied on the
/// consumer's task cancellation (via `onTermination`) to drop the subscriber
/// from the actor's bookkeeping. A caller that obtained the stream and either
/// abandoned it without iterating, or broke out of `for-await` normally, would
/// leave a stale entry until the next broadcast caught `.terminated`. The
/// `Subscription` token is itself the `AsyncSequence`, and its iterator
/// strongly retains the token — so iteration cannot outlive ownership.
/// Dropping every reference (token + iterators) deterministically removes
/// the subscriber slot — Combine's `AnyCancellable` pattern.
@Suite("RecorderSubscription", .timeLimit(.minutes(1)))
struct RecorderSubscriptionTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Subscription IS the AsyncSequence

    @Test func subscription_isIterable() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let subscription = await recorder.subscribeEvents()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            var observed: [Recorder.Event] = []
            for await event in subscription {
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

    // MARK: - Cleanup-on-drop (the gap fix)

    @Test func subscription_droppedWithoutIterating_removesSubscriber() async throws {
        // Caller obtains the subscription but never iterates. After
        // dropping the subscription, the actor must observe its
        // subscribers map go back to empty.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            do {
                let transient = await recorder.subscribeEvents()
                let mid = await recorder.subscriberCount
                #expect(mid == 1)
                // Reference `transient` after the await so ARC keeps
                // it alive through the count check. Without this, the
                // compiler is free to release the binding immediately
                // after subscribeEvents returns and the deinit cleanup
                // races the count check.
                _ = transient
            }
            // Subscription dropped → deinit fires cleanup Task. Yield
            // until the Task reaches the actor.
            for _ in 0..<50 { await Task.megaYield() }
            let final = await recorder.subscriberCount
            #expect(final == 0)
        }
    }

    @Test func subscription_droppedAfterNormalBreak_removesSubscriber() async throws {
        // Caller iterates, breaks normally (no cancellation), then drops
        // the subscription. The break drops the iterator but the token
        // binding is still alive — only the deinit path drives cleanup.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            do {
                let subscription = await recorder.subscribeEvents()
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
                for await _ in subscription { break }
                let mid = await recorder.subscriberCount
                #expect(mid == 1)
                _ = subscription
            }
            for _ in 0..<50 { await Task.megaYield() }
            let final = await recorder.subscriberCount
            #expect(final == 0)
        }
    }

    @Test func multipleSubscriptions_independentCleanup() async throws {
        // Two subscriptions; dropping one must not affect the other.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let persistent = await recorder.subscribeEvents()
            do {
                let transient = await recorder.subscribeEvents()
                let mid = await recorder.subscriberCount
                #expect(mid == 2)
                _ = transient
            }
            for _ in 0..<50 { await Task.megaYield() }
            let after = await recorder.subscriberCount
            #expect(after == 1)
            // persistent is still alive — broadcast should still reach it.
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
}
