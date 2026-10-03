//
//  ContextualQuestionSessionTests.swift
//  EasydictTests
//
//  Created by Eric Pan on 2026/9/17.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Defaults
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

    @MainActor
    @Test("Reusing a query result cancels and clears its contextual question")
    func queryResultResetCancelsOwnedQuestion() async {
        let result = QueryResult()
        let session = ContextualQuestionSession()
        let provider = ControlledContextualQuestionProvider()
        result.contextualQuestionSession = session
        session.draft = "Explain this concept"
        session.setExpanded(true)
        #expect(session.submit(request: request(), provider: provider))
        provider.yield("Answer from the previous query")
        #expect(await waitUntil { session.phase == .streaming })

        result.reset()
        #expect(await waitUntil { provider.cancelledRequestCount == 1 })
        provider.yield("Late answer from the previous query")
        provider.finish()
        await drainScheduledTasks()

        #expect(result.contextualQuestionSession == nil)
        #expect(session.phase == .idle)
        #expect(!session.isRunning)
        #expect(session.submittedQuestion.isEmpty)
        #expect(session.answer.isEmpty)
        #expect(session.failureMessage == nil)
        #expect(session.draft.isEmpty)
        #expect(!session.isExpanded)
    }

    @MainActor
    @Test("Anki and Markdown toolbar actions coexist with repeated contextual question expansion")
    func resultToolbarPreservesQuestionInteraction() async throws {
        let domainName = try #require(Bundle.main.bundleIdentifier)
        let ankiSettingKey = "enableAnkiConnect"
        let previousAnkiSetting = UserDefaults.standard.persistentDomain(forName: domainName)?[ankiSettingKey]
        Defaults[.enableAnkiConnect] = true
        defer {
            if let previousAnkiSetting {
                UserDefaults.standard.set(previousAnkiSetting, forKey: ankiSettingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ankiSettingKey)
            }
        }
        let result = QueryResult()
        result.queryText = "Synthetic dictionary example"
        result.translatedResults = ["用于工具栏回归验证的合成释义。"]
        result.wordResult = EZTranslateWordResult()
        result.from = .english
        result.to = .simplifiedChinese
        result.isStreamFinished = true
        let service = DeepSeekService()
        service.result = result
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        // The Objective-C card header is not imported by the Swift test target.
        let cardType = try #require(NSClassFromString("EZWordResultView") as? NSView.Type)
        let card = cardType.init(frame: NSRect(x: 12, y: 12, width: 576, height: 300))
        card.setValue(service, forKey: "service")
        let updateHeight: @convention(block) (CGFloat) -> () = { [weak card] height in
            card?.setFrameSize(NSSize(width: 576, height: height))
        }
        card.setValue(updateHeight, forKey: "updateViewHeightBlock")
        let viewHeight = {
            CGFloat((card.value(forKey: "viewHeight") as? NSNumber)?.doubleValue ?? 0)
        }
        window.contentView?.addSubview(card)
        card.perform(NSSelectorFromString("refreshWithResult:"), with: result)
        card.setFrameSize(NSSize(width: 576, height: viewHeight()))
        card.layoutSubtreeIfNeeded()

        let session = try #require(result.contextualQuestionSession)
        let questionButton = try #require(card.subviews.compactMap { $0 as? ContextualQuestionButton }.first)
        let panel = try #require(card.subviews.compactMap { $0 as? ContextualQuestionView }.first)
        let markdownButton = try #require(card.subviews.compactMap { $0 as? MarkdownToggleButton }.first)
        let ankiButton = try #require(card.subviews.compactMap { $0 as? NSButton }.first {
            $0.toolTip == String(localized: "anki.connect.add_button")
        })
        let input = try #require(panel.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        let collapsedHeight = viewHeight()
        #expect(questionButton.isEnabled)
        #expect(panel.isHidden)

        for cycle in 0 ..< 3 {
            questionButton.performClick(nil)
            #expect(try await waitForUI {
                session.isExpanded && !panel.isHidden && panel.preferredHeight > 0 && viewHeight() > collapsedHeight
            })
            card.layoutSubtreeIfNeeded()
            panel.layoutSubtreeIfNeeded()
            #expect(!input.isHiddenOrHasHiddenAncestor)
            #expect(input.isEnabled && input.frame.width > 80 && input.frame.height > 0)
            #expect(ankiButton.frame.width > 0 && markdownButton.frame.width > 0 && questionButton.frame.width > 0)
            #expect(ankiButton.frame.maxX <= markdownButton.frame.minX)
            #expect(markdownButton.frame.maxX <= questionButton.frame.minX)

            if cycle == 0 {
                input.stringValue = "Explain this synthetic example"
                panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
                let bitmap = try #require(card.bitmapImageRepForCachingDisplay(in: card.bounds))
                card.cacheDisplay(in: card.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let screenshot = FileManager.default.temporaryDirectory
                    .appendingPathComponent("easydict-contextual-toolbar-expanded.png")
                try png.write(to: screenshot, options: .atomic)
                print("Synthetic contextual toolbar rendering: \(screenshot.path)")
            }
            #expect(session.draft == "Explain this synthetic example")
            #expect(input.stringValue == session.draft)

            questionButton.performClick(nil)
            #expect(try await waitForUI {
                !session.isExpanded && panel.isHidden && panel.preferredHeight == 0
                    && abs(viewHeight() - collapsedHeight) < 0.5
            })
            #expect(session.draft == "Explain this synthetic example")
        }
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

    @MainActor
    private func waitForUI(predicate: () -> Bool) async throws -> Bool {
        for _ in 0 ..< 100 {
            if predicate() { return true }
            try await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
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

    var cancelledRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellationCount
    }

    func contextualQuestionStream(
        _ request: ContextualQuestionRequest
    )
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination, let self else { return }
                lock.lock()
                cancellationCount += 1
                lock.unlock()
            }
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
    private var cancellationCount = 0

    private func currentContinuation() -> Continuation? {
        lock.lock()
        defer { lock.unlock() }
        return continuation
    }
}
