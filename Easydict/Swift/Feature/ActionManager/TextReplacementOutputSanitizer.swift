//
//  TextReplacementOutputSanitizer.swift
//  Easydict
//
//  Created by victoryuanxichen on 2026/10/18.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - TextReplacementOutputSanitizer

/// Removes conversational wrappers that LLMs sometimes add around replacement text.
///
/// Replacement chunks are inserted immediately and cannot be withdrawn, so the sanitizer only
/// holds back the response head until a leading `<think>` block, preamble such as
/// "Okay, here is the translation:", or wrapper (code fence, triple quotes, quotes) can be ruled
/// out, and holds back trailing whitespace or a candidate closing delimiter until the stream
/// ends. The head is re-evaluated as a whole on every chunk and only resolved once no rule can
/// still match, so the result does not depend on chunk boundaries. Each rule is skipped when the
/// source text itself starts the same way, so genuine content such as a translated "Note:"
/// heading or a quoted sentence is preserved.
struct TextReplacementOutputSanitizer {
    // MARK: Lifecycle

    init(sourceText: String) {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = String(trimmedSource.prefix { !$0.isNewline })

        self.sourceStart = String(trimmedSource.prefix(Self.fence.count))
        self.sourceStartsWithQuote = trimmedSource.first.map { Self.quotePairs.keys.contains($0) } ?? false
        self.preservesLeadingWhitespace = sourceText.first?.isWhitespace ?? false
        self.preservesTrailingWhitespace = sourceText.last?.isWhitespace ?? false
        self.allowsPreambleRemoval = !firstLine.contains { $0 == ":" || $0 == "：" } &&
            !Self.mentionsResult(firstLine)
    }

    // MARK: Internal

    /// Returns the part of the accumulated output that is safe to insert after `chunk`.
    mutating func consume(_ chunk: String) -> String {
        switch phase {
        case .head:
            head += chunk
            guard let resolution = resolveHead(isFinal: false) else { return "" }
            return enterBody(resolution)
        case .body:
            return streamBody(chunk)
        case .bufferedQuote:
            pending += chunk
            return ""
        case .finished:
            return ""
        }
    }

    /// Returns the held-back remainder once the provider stream has completed.
    mutating func finish() -> String {
        var output = ""
        if case .head = phase, let resolution = resolveHead(isFinal: true) {
            output += enterBody(resolution)
        }

        switch phase {
        case .body:
            output += finishBody()
        case let .bufferedQuote(open, close):
            output += finishBufferedQuote(open: open, close: close)
        case .finished, .head:
            break
        }

        phase = .finished
        pending = ""
        return output
    }

    // MARK: Private

    private enum Phase {
        case head
        case body
        case bufferedQuote(open: Character, close: Character)
        case finished
    }

    private struct HeadResolution {
        var body: String
        var closingDelimiter: String?
        var quotePair: (open: Character, close: Character)?
    }

    private enum PreambleMatch {
        case none
        case undecided
        case matched(length: Int)
    }

    /// Bounds how long the head may be buffered while waiting to rule out a preamble or wrapper.
    private static let maxHeadLength = 160

    private static let thinkOpenTag = "<think>"
    private static let thinkCloseTag = "</think>"
    private static let fence = "```"
    private static let tripleQuote = "\"\"\""

    private static let quotePairs: [Character: Character] = [
        "\"": "\"",
        "“": "”",
        "‘": "’",
        "「": "」",
        "『": "』",
    ]

    /// Acknowledgements are only removed together with a following introduction line, never on
    /// their own, because a translated "Of course!" line is indistinguishable from chatter.
    private static let acknowledgementTokens = [
        "okay", "ok", "sure", "certainly", "of course", "alright", "all right", "got it",
        "no problem", "好的", "好", "当然", "當然", "没问题", "沒問題", "明白", "收到",
    ]

    private static let introductionTokens = [
        "here is", "here's", "here’s", "here are", "below is", "the translation",
        "the translated", "translation", "translated", "the polished", "polished",
        "the revised", "revised", "the improved", "improved", "以下是", "下面是", "这是", "這是",
        "翻译", "翻譯", "译文", "譯文", "润色", "潤色", "修改后", "修改後", "优化后", "優化後",
    ]

    /// An introduction line is only a preamble when it names the result, so translated content
    /// such as "Here are my suggestions:" keeps its first line.
    private static let resultKeywords = [
        "translat", "polish", "revised", "rewritten", "improved version", "翻译", "翻譯", "译文",
        "譯文", "译为", "譯為", "润色", "潤色", "修改后", "修改後", "优化后", "優化後",
    ]

    /// Matches a leading acknowledgement and the separators after it, including line breaks.
    private static let acknowledgementRegex = makeRegex(
        "^(?:\(alternation(acknowledgementTokens)))[\\s,，.。!！~～]*"
    )

    /// Matches an introduction line that ends with a colon, plus the whitespace after it.
    private static let introductionRegex = makeRegex(
        "^(?:\(alternation(introductionTokens)))[^\\n:：]{0,80}[:：]\\s*"
    )

    private let sourceStart: String
    private let sourceStartsWithQuote: Bool
    private let preservesLeadingWhitespace: Bool
    private let preservesTrailingWhitespace: Bool
    private let allowsPreambleRemoval: Bool

    private var phase = Phase.head
    private var head = ""
    private var pending = ""
    private var closingDelimiter: String?

    private static func alternation(_ tokens: [String]) -> String {
        tokens
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // Patterns are built from static tokens, so a failure is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func mentionsResult(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        return resultKeywords.contains { lowercasedText.contains($0) }
    }

    /// Returns the character count of an anchored match, if any.
    private static func matchLength(of regex: NSRegularExpression, in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [.anchored], range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        return text.distance(from: text.startIndex, to: matchRange.upperBound)
    }

    /// Whether `index` is a trailing lone carriage return that may still join a following "\n".
    private static func mayContinueLineBreak(_ text: Substring, at index: Substring.Index) -> Bool {
        text[index] == "\r" && text.index(after: index) == text.endIndex
    }

    // MARK: Head

    /// Decides how the buffered head starts, or returns nil while more output is needed.
    private func resolveHead(isFinal: Bool) -> HeadResolution? {
        var rest = Substring(head)
        let leadingWhitespace = rest.prefix { $0.isWhitespace }
        rest = rest.dropFirst(leadingWhitespace.count)
        var didStrip = false

        // Keep stripping `<think>` blocks and preambles until neither applies.
        stripping: while true {
            if rest.hasPrefix(Self.thinkOpenTag) {
                guard let closeRange = rest.range(of: Self.thinkCloseTag) else {
                    return isFinal ? HeadResolution(body: "") : nil
                }
                rest = rest[closeRange.upperBound...].drop { $0.isWhitespace }
                didStrip = true
                continue
            }
            // Covers an empty head, which can always still grow into a `<think>` tag.
            if !isFinal, Self.thinkOpenTag.hasPrefix(rest) {
                return nil
            }
            guard allowsPreambleRemoval else { break }

            switch preambleMatch(in: rest, isFinal: isFinal) {
            case .undecided:
                return nil
            case let .matched(length):
                rest = rest.dropFirst(length).drop { $0.isWhitespace }
                didStrip = true
            case .none:
                break stripping
            }
        }

        if !sourceStart.hasPrefix(Self.fence) {
            if rest.hasPrefix(Self.fence) {
                // The opening fence line, including any language tag, is dropped with its line
                // break; the content keeps its own indentation.
                if let lineBreak = rest.firstIndex(where: \.isNewline) {
                    if !isFinal, Self.mayContinueLineBreak(rest, at: lineBreak) {
                        return nil
                    }
                    rest = rest[rest.index(after: lineBreak)...]
                } else if isFinal || rest.count >= Self.maxHeadLength {
                    rest = rest.dropFirst(Self.fence.count)
                } else {
                    return nil
                }
                return HeadResolution(body: String(rest), closingDelimiter: Self.fence)
            }
            if !isFinal, Self.fence.hasPrefix(rest) {
                return nil
            }
        }

        if !sourceStart.hasPrefix(Self.tripleQuote) {
            if rest.hasPrefix(Self.tripleQuote) {
                var body = rest.dropFirst(Self.tripleQuote.count)
                if let first = body.first, first.isNewline {
                    if !isFinal, Self.mayContinueLineBreak(body, at: body.startIndex) {
                        return nil
                    }
                    body = body.dropFirst()
                } else if body.isEmpty, !isFinal {
                    // Wait to see whether the delimiter is followed by its own line break.
                    return nil
                }
                return HeadResolution(body: String(body), closingDelimiter: Self.tripleQuote)
            }
            if !isFinal, Self.tripleQuote.hasPrefix(rest) {
                return nil
            }
        }

        if let open = rest.first,
           let close = Self.quotePairs[open],
           !sourceStartsWithQuote {
            return HeadResolution(body: String(rest), quotePair: (open, close))
        }

        let keepsLeadingWhitespace = preservesLeadingWhitespace && !didStrip
        return HeadResolution(body: (keepsLeadingWhitespace ? String(leadingWhitespace) : "") + rest)
    }

    /// Matches an optional acknowledgement followed by an introduction line that names the result.
    private func preambleMatch(in rest: Substring, isFinal: Bool) -> PreambleMatch {
        let text = String(rest)
        let lowercasedText = text.lowercased()

        // Wait while the head could still grow into a longer acknowledgement ("Ok" -> "Okay").
        if !isFinal, Self.acknowledgementTokens.contains(where: { $0.hasPrefix(lowercasedText) }) {
            return .undecided
        }

        let acknowledgementLength = Self.matchLength(of: Self.acknowledgementRegex, in: text) ?? 0
        let remainder = String(text.dropFirst(acknowledgementLength))
        if remainder.isEmpty {
            return isFinal ? .none : .undecided
        }

        let lowercasedRemainder = remainder.lowercased()
        let mayStartIntroduction = Self.introductionTokens.contains {
            lowercasedRemainder.hasPrefix($0) || $0.hasPrefix(lowercasedRemainder)
        }
        guard mayStartIntroduction else { return .none }

        if let introductionLength = Self.matchLength(of: Self.introductionRegex, in: remainder) {
            let length = acknowledgementLength + introductionLength
            guard Self.mentionsResult(String(text.prefix(length))) else { return .none }
            // Trailing whitespace may continue in the next chunk, so wait for real content.
            return length < text.count || isFinal ? .matched(length: length) : .undecided
        }

        let isDecided = isFinal || remainder.contains(where: \.isNewline) ||
            text.count >= Self.maxHeadLength
        return isDecided ? .none : .undecided
    }

    private mutating func enterBody(_ resolution: HeadResolution) -> String {
        head = ""
        closingDelimiter = resolution.closingDelimiter
        if let quotePair = resolution.quotePair {
            phase = .bufferedQuote(open: quotePair.open, close: quotePair.close)
            pending = resolution.body
            return ""
        }
        phase = .body
        return streamBody(resolution.body)
    }

    // MARK: Body

    /// Emits everything except trailing whitespace and a possible closing delimiter.
    private mutating func streamBody(_ chunk: String) -> String {
        let combined = pending + chunk
        var splitIndex = Self.trailingWhitespaceStart(in: combined)
        if let closingDelimiter {
            splitIndex = combined.index(
                splitIndex,
                offsetBy: -closingDelimiter.count,
                limitedBy: combined.startIndex
            ) ?? combined.startIndex
            splitIndex = Self.trailingWhitespaceStart(in: combined[..<splitIndex])
        }
        pending = String(combined[splitIndex...])
        return String(combined[..<splitIndex])
    }

    /// Drops a closing delimiter, then applies the same trailing whitespace rule as unwrapped output.
    private mutating func finishBody() -> String {
        var content = pending
        if let closingDelimiter {
            let core = content[..<Self.trailingWhitespaceStart(in: content)]
            if core.hasSuffix(closingDelimiter) {
                content = String(core.dropLast(closingDelimiter.count))
            }
        }
        return applyingTrailingWhitespaceRule(to: content)
    }

    private func finishBufferedQuote(open: Character, close: Character) -> String {
        var content = pending
        let core = content[..<Self.trailingWhitespaceStart(in: content)]
        if core.count >= 2, core.first == open, core.last == close {
            let inner = core.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) {
                content = String(inner)
            }
        }
        return applyingTrailingWhitespaceRule(to: content)
    }

    /// Keeps trailing whitespace only when the source text also ends with whitespace.
    private func applyingTrailingWhitespaceRule(to text: String) -> String {
        preservesTrailingWhitespace ? text : String(text[..<Self.trailingWhitespaceStart(in: text)])
    }

    private static func trailingWhitespaceStart<S: StringProtocol>(in text: S) -> String.Index {
        var index = text.endIndex
        while index > text.startIndex {
            let previousIndex = text.index(before: index)
            guard text[previousIndex].isWhitespace else { break }
            index = previousIndex
        }
        return index
    }
}

// MARK: - Stream Filtering

extension TextReplacementOutputSanitizer {
    /// Wraps a provider stream so only sanitized content reaches the insertion session.
    ///
    /// Held-back content is flushed on provider failure only after something was already
    /// yielded, so an attempt that fails while its head is still buffered stays eligible for
    /// the built-in fallback.
    static func sanitizing(
        _ stream: AsyncThrowingStream<String, Error>,
        sourceText: String
    )
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sanitizer = TextReplacementOutputSanitizer(sourceText: sourceText)
                var didYield = false

                func yield(_ content: String) {
                    guard !content.isEmpty else { return }
                    didYield = true
                    continuation.yield(content)
                }

                do {
                    for try await chunk in stream {
                        yield(sanitizer.consume(chunk))
                    }
                    yield(sanitizer.finish())
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    if didYield {
                        yield(sanitizer.finish())
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
