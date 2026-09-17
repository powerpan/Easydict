//
//  ContextualQuestionSession.swift
//  Easydict
//
//  Created by Eric Pan on 2026/9/17.
//  Copyright © 2026 izual. All rights reserved.
//

import Combine
import Foundation

/// Owns the transient state and exact cancellation boundary for one result-card question.
/// A request identifier rejects late chunks after reset or replacement, while all published
/// content remains in memory and is discarded with the owning query result.
@objc(EDContextualQuestionSession)
final class ContextualQuestionSession: NSObject, ObservableObject {
    // MARK: Internal

    // MARK: ContextualQuestionPhase

    @objc(EDContextualQuestionPhase)
    enum Phase: Int {
        case idle
        case requesting
        case streaming
        case succeeded
        case failed
        case cancelled
    }

    static let maximumQuestionCharacterCount = 2_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var submittedQuestion = ""
    @Published private(set) var answer = ""
    @Published private(set) var failureMessage: String?
    @Published var draft = ""
    @Published private(set) var isExpanded = false

    var isRunning: Bool {
        phase == .requesting || phase == .streaming
    }

    @objc
    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    @objc
    func toggleExpanded() {
        isExpanded.toggle()
    }

    /// Starts one independent question. Validation failures publish a localized card state;
    /// a concurrent submission is rejected without disturbing the active request.
    @discardableResult
    func submit(
        request: ContextualQuestionRequest,
        provider: ContextualQuestionStreaming
    )
        -> Bool {
        guard !isRunning else {
            return false
        }

        guard !request.question.trim().isEmpty else {
            fail(with: ContextualQuestionError.emptyQuestion)
            return false
        }

        guard request.question.count <= Self.maximumQuestionCharacterCount else {
            fail(
                with: ContextualQuestionError.questionTooLong(
                    maximum: Self.maximumQuestionCharacterCount
                )
            )
            return false
        }

        guard !request.sourceText.isEmpty, !request.translatedText.isEmpty else {
            fail(with: ContextualQuestionError.unavailableContext)
            return false
        }

        let requestID = UUID()
        activeRequestID = requestID
        submittedQuestion = request.question
        answer = ""
        failureMessage = nil
        phase = .requesting

        let stream = provider.contextualQuestionStream(request)
        requestTask = Task { @MainActor [weak self] in
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    guard !chunk.isEmpty else { continue }
                    self?.receive(chunk, requestID: requestID)
                }

                self?.finish(requestID: requestID)
            } catch is CancellationError {
                self?.finishCancellation(requestID: requestID)
            } catch {
                self?.finish(error: error, requestID: requestID)
            }
        }
        return true
    }

    /// Stops only the currently owned question request and preserves partial output.
    @objc
    func cancel() {
        guard isRunning else { return }

        activeRequestID = nil
        requestTask?.cancel()
        requestTask = nil
        phase = .cancelled
        failureMessage = answer.isEmpty
            ? String(localized: "contextual_question.status.cancelled")
            : String(localized: "contextual_question.status.cancelled_partial")
    }

    /// Cancels network work and removes every user-visible value before result reuse.
    @objc
    func reset() {
        activeRequestID = nil
        requestTask?.cancel()
        requestTask = nil
        phase = .idle
        submittedQuestion = ""
        answer = ""
        failureMessage = nil
        draft = ""
        isExpanded = false
    }

    func failProviderUnavailable() {
        fail(with: ContextualQuestionError.unavailableProvider)
    }

    // MARK: Private

    private var activeRequestID: UUID?
    private var requestTask: Task<(), Never>?

    private func receive(_ chunk: String, requestID: UUID) {
        guard activeRequestID == requestID else { return }
        answer += chunk
        phase = .streaming
    }

    private func finish(requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        requestTask = nil

        guard !answer.isEmpty else {
            fail(with: ContextualQuestionError.emptyResponse)
            return
        }

        phase = .succeeded
        failureMessage = nil
    }

    private func finishCancellation(requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        requestTask = nil
        phase = .cancelled
        failureMessage = answer.isEmpty
            ? String(localized: "contextual_question.status.cancelled")
            : String(localized: "contextual_question.status.cancelled_partial")
    }

    private func finish(error: Error, requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        requestTask = nil
        phase = .failed
        failureMessage = answer.isEmpty
            ? safeMessage(for: error)
            : String(localized: "contextual_question.error.interrupted")
    }

    private func fail(with error: ContextualQuestionError) {
        phase = .failed
        failureMessage = error.localizedDescription
    }

    private func safeMessage(for error: Error) -> String {
        guard let queryError = error as? QueryError else {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                return String(localized: "contextual_question.error.timeout")
            }
            return String(localized: "contextual_question.error.provider")
        }

        switch queryError.type {
        case .missingSecretKey:
            return String(localized: "contextual_question.error.authentication")
        case .timeout:
            return String(localized: "contextual_question.error.timeout")
        case .contentTypeMismatch,
             .parameter,
             .unsupportedLanguage,
             .unsupportedQueryType,
             .unsupportedServiceType:
            return String(localized: "contextual_question.error.configuration")
        case .api, .appleScript, .noResult, .unknown:
            return String(localized: "contextual_question.error.provider")
        }
    }
}
