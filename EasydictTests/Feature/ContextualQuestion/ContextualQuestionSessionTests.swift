//
//  ContextualQuestionSessionTests.swift
//  EasydictTests
//
//  Created by Eric Pan on 2026/9/17.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - ContextualQuestionSessionTests

@Suite("Contextual Question Session", .serialized, .tags(.unit))
struct ContextualQuestionSessionTests {
    // MARK: Internal

    @MainActor
    @Test("Streams response chunks in order and completes successfully")
    func streamsResponseToCompletion() async {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        #expect(session.submit(request: request(), provider: provider))
        #expect(session.phase == .requesting)

        provider.yield("Governance")
        provider.yield("-native")
        provider.yield(" systems")
        provider.finish()

        #expect(await waitUntil { session.phase == .succeeded })
        #expect(session.answer == "Governance-native systems")
        #expect(session.submittedQuestion == "Explain this concept")
        #expect(session.failureMessage == nil)
        #expect(provider.requestCount == 1)
    }

    @MainActor
    @Test("Reports an empty provider response without inventing content")
    func reportsEmptyResponse() async {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        #expect(session.submit(request: request(), provider: provider))
        provider.finish()

        #expect(await waitUntil { session.phase == .failed })
        #expect(session.answer.isEmpty)
        #expect(session.failureMessage == ContextualQuestionError.emptyResponse.localizedDescription)
    }

    @MainActor
    @Test("Rejects a blank question before opening a provider stream")
    func rejectsBlankQuestion() {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        let accepted = session.submit(
            request: request(question: " \n\t "),
            provider: provider
        )

        #expect(!accepted)
        #expect(session.phase == .failed)
        #expect(session.answer.isEmpty)
        #expect(session.failureMessage == ContextualQuestionError.emptyQuestion.localizedDescription)
        #expect(provider.requestCount == 0)
    }

    @MainActor
    @Test("Rejects a question over the documented character limit")
    func rejectsOverlongQuestion() {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()
        let maximum = ContextualQuestionSession.maximumQuestionCharacterCount

        let accepted = session.submit(
            request: request(question: String(repeating: "問", count: maximum + 1)),
            provider: provider
        )

        #expect(!accepted)
        #expect(session.phase == .failed)
        #expect(
            session.failureMessage == ContextualQuestionError
                .questionTooLong(maximum: maximum)
                .localizedDescription
        )
        #expect(provider.requestCount == 0)
    }

    @MainActor
    @Test("Rejects a duplicate submit while preserving the active request")
    func rejectsDuplicateSubmit() async {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        #expect(session.submit(request: request(), provider: provider))
        #expect(!session.submit(request: request(question: "A second question"), provider: provider))
        #expect(session.isRunning)
        #expect(session.phase == .requesting)
        #expect(session.submittedQuestion == "Explain this concept")
        #expect(provider.requestCount == 1)

        provider.yield("Answer")
        provider.finish()

        #expect(await waitUntil { session.phase == .succeeded })
        #expect(session.answer == "Answer")
    }

    @MainActor
    @Test("Cancellation preserves partial output and ignores later chunks")
    func cancellationPreservesPartialOutput() async {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        #expect(session.submit(request: request(), provider: provider))
        provider.yield("Partial answer")
        #expect(await waitUntil { session.answer == "Partial answer" })

        session.cancel()
        provider.yield(" that arrived too late")
        provider.finish()
        await drainScheduledTasks()

        #expect(session.phase == .cancelled)
        #expect(session.answer == "Partial answer")
        #expect(
            session.failureMessage == String(
                localized: "contextual_question.status.cancelled_partial"
            )
        )
    }

    @MainActor
    @Test("Reset clears state and rejects chunks from the invalidated request")
    func resetRejectsLateChunks() async {
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()

        session.draft = "Explain this concept"
        session.setExpanded(true)
        #expect(session.submit(request: request(), provider: provider))

        session.reset()
        provider.yield("Late answer")
        provider.finish()
        await drainScheduledTasks()

        #expect(session.phase == .idle)
        #expect(session.submittedQuestion.isEmpty)
        #expect(session.answer.isEmpty)
        #expect(session.failureMessage == nil)
        #expect(session.draft.isEmpty)
        #expect(!session.isExpanded)
    }

    // MARK: Private

    private func request(
        question: String = "Explain this concept"
    )
        -> ContextualQuestionRequest {
        ContextualQuestionRequest(
            sourceText: "Policy-Aware Runtime",
            translatedText: "策略感知运行时",
            sourceLanguage: .english,
            targetLanguage: .traditionalChinese,
            question: question
        )
    }

    @MainActor
    private func waitUntil(
        attempts: Int = 2_000,
        predicate: () -> Bool
    ) async
        -> Bool {
        for _ in 0 ..< attempts {
            if predicate() {
                return true
            }
            await Task.yield()
        }
        return predicate()
    }

    private func drainScheduledTasks(iterations: Int = 100) async {
        for _ in 0 ..< iterations {
            await Task.yield()
        }
    }
}

// MARK: - ControlledContextualQuestionProvider

/// A deterministic in-memory provider. It never opens a URLSession and lets each test
/// control the exact stream termination boundary.
private final class ControlledContextualQuestionProvider: ContextualQuestionStreaming,
    @unchecked Sendable {
    // MARK: Internal

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests.count
    }

    func contextualQuestionStream(
        _ request: ContextualQuestionRequest
    )
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            capturedRequests.append(request)
            self.continuation = continuation
            lock.unlock()
        }
    }

    func yield(_ chunk: String) {
        currentContinuation()?.yield(chunk)
    }

    func finish() {
        currentContinuation()?.finish()
    }

    // MARK: Private

    private typealias Continuation = AsyncThrowingStream<String, Error>.Continuation

    private let lock = NSLock()
    private var capturedRequests: [ContextualQuestionRequest] = []
    private var continuation: Continuation?

    private func currentContinuation() -> Continuation? {
        lock.lock()
        defer { lock.unlock() }
        return continuation
    }
}
