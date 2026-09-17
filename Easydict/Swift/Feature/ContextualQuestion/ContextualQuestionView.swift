//
//  ContextualQuestionView.swift
//  Easydict
//
//  Created by Eric Pan on 2026/9/17.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import SFSafeSymbols

/// AppKit panel for one contextual question and its streamed answer.
/// The panel projects session state without owning request lifetime, allowing table-cell reloads
/// to rebuild the view while the owning `QueryResult` preserves the active session.
@objc(EDContextualQuestionView)
final class ContextualQuestionView: NSView, NSTextFieldDelegate {
    // MARK: Lifecycle

    @objc
    init(
        session: ContextualQuestionSession,
        service: QueryService,
        result: QueryResult
    ) {
        self.session = session
        self.service = service
        self.result = result
        super.init(frame: .zero)
        configure()
        bindSession()
        render()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: Internal

    override var isFlipped: Bool { true }

    @objc private(set) var preferredHeight: CGFloat = 0

    @objc var heightDidChange: ((CGFloat) -> ())?

    @objc var availableWidth: CGFloat = 320 {
        didSet {
            guard abs(oldValue - availableWidth) > 0.5 else { return }
            scheduleHeightUpdate()
        }
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, abs(bounds.width - availableWidth) > 0.5 {
            availableWidth = bounds.width
        }
        layoutContent()
    }

    func controlTextDidChange(_ notification: Notification) {
        session.draft = inputField.stringValue
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    )
        -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submitOrCancel()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            session.setExpanded(false)
            return true
        default:
            return false
        }
    }

    // MARK: Private

    private enum Layout {
        static let inputHeight: CGFloat = 30
        static let actionButtonWidth: CGFloat = 28
        static let sectionSpacing: CGFloat = 8
        static let textSpacing: CGFloat = 4
        static let answerHeaderHeight: CGFloat = 22
        static let statusMinimumHeight: CGFloat = 16
        static let answerFontSize: CGFloat = 14
    }

    private let session: ContextualQuestionSession
    private let service: QueryService
    private let result: QueryResult

    private let inputField = NSTextField()
    private let actionButton = EZHoverButton()
    private let answerHeader = NSTextField(
        labelWithString: String(localized: "contextual_question.label.answer")
    )
    private let answerCopyButton = EZHoverButton()
    private let answerLabel = MarkdownLabel()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private var cancellables: Set<AnyCancellable> = []
    private var heightUpdateWorkItem: DispatchWorkItem?

    private var contentWidth: CGFloat {
        max(availableWidth, 120)
    }

    private var statusText: String {
        switch session.phase {
        case .idle, .succeeded:
            return ""
        case .requesting:
            return String(localized: "contextual_question.status.requesting")
        case .streaming:
            return String(localized: "contextual_question.status.streaming")
        case .cancelled, .failed:
            return session.failureMessage ?? ""
        }
    }

    private var calculatedHeight: CGFloat {
        guard session.isExpanded else { return 0 }

        var height = Layout.inputHeight
        if !session.answer.isEmpty {
            height += Layout.sectionSpacing + Layout.answerHeaderHeight
            height += Layout.textSpacing + answerHeight
        }
        if !statusText.isEmpty {
            height += Layout.textSpacing + statusHeight
        }
        return ceil(height)
    }

    private var answerHeight: CGFloat {
        answerLabel.text = session.answer
        let inset = answerLabel.textContainerInset
        let renderWidth = max(contentWidth - inset.width * 2, 1)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: renderWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = answerLabel.textContainer?.lineFragmentPadding ?? 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage(
            attributedString: answerLabel.textStorage ?? NSTextStorage()
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.glyphRange(for: textContainer)

        let textHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        return max(textHeight + inset.height * 2, Layout.statusMinimumHeight)
    }

    private var statusHeight: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: statusLabel.font as Any]
        let rect = (statusText as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return max(ceil(rect.height), Layout.statusMinimumHeight)
    }

    private func configure() {
        wantsLayer = true

        inputField.delegate = self
        inputField.placeholderString = String(localized: "contextual_question.input.placeholder")
        inputField.font = .systemFont(ofSize: 13)
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .default
        inputField.setAccessibilityLabel(
            String(localized: "contextual_question.input.accessibility_label")
        )
        addSubview(inputField)

        actionButton.cornerRadius = 5
        actionButton.clickBlock = { [weak self] _ in
            self?.submitOrCancel()
        }
        addSubview(actionButton)

        answerHeader.font = .systemFont(ofSize: 12, weight: .semibold)
        answerHeader.textColor = .secondaryLabelColor
        addSubview(answerHeader)

        answerCopyButton.clickBlock = { [weak self] _ in
            self?.session.answer.copyAndShowToast(true)
        }
        answerCopyButton.cornerRadius = 5
        answerCopyButton.image = NSImage(systemSymbol: .docOnDoc)
        answerCopyButton.toolTip = String(localized: "contextual_question.action.copy_answer")
        answerCopyButton.setAccessibilityLabel(
            String(localized: "contextual_question.action.copy_answer")
        )
        addSubview(answerCopyButton)

        answerLabel.font = .systemFont(ofSize: Layout.answerFontSize)
        answerLabel.markdownEnabled = result.isMarkdownRenderingEnabled
        addSubview(answerLabel)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        addSubview(statusLabel)

        executeOnAppearanceChange { [weak self] _, _ in
            self?.applyActionButtonAppearance()
        }
    }

    private func bindSession() {
        session.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.render()
                guard expanded else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    window?.makeFirstResponder(inputField)
                }
            }
            .store(in: &cancellables)

        session.$phase
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        session.$answer
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        session.$failureMessage
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        session.$draft
            .removeDuplicates()
            .sink { [weak self] draft in
                guard let self, inputField.stringValue != draft else { return }
                inputField.stringValue = draft
            }
            .store(in: &cancellables)
    }

    private func render() {
        isHidden = !session.isExpanded
        inputField.isEnabled = !session.isRunning
        inputField.stringValue = session.draft

        answerLabel.text = session.answer
        let hasAnswer = !session.answer.isEmpty
        answerHeader.isHidden = !hasAnswer
        answerCopyButton.isHidden = !hasAnswer
        answerLabel.isHidden = !hasAnswer

        statusLabel.stringValue = statusText
        statusLabel.isHidden = statusLabel.stringValue.isEmpty

        applyActionButtonAppearance()
        needsLayout = true
        scheduleHeightUpdate()
    }

    private func applyActionButtonAppearance() {
        let activeColor: NSColor = isDarkMode ? .ez_imageTintDark() : .ez_imageTintLight()
        actionButton.contentTintColor = activeColor
        answerCopyButton.contentTintColor = activeColor

        if session.isRunning {
            actionButton.image = NSImage(systemSymbol: .stopCircle)
            actionButton.toolTip = String(localized: "contextual_question.action.stop")
            actionButton.setAccessibilityLabel(
                String(localized: "contextual_question.action.stop")
            )
        } else {
            actionButton.image = NSImage(systemSymbol: .paperplaneFill)
            actionButton.toolTip = String(localized: "contextual_question.action.send")
            actionButton.setAccessibilityLabel(
                String(localized: "contextual_question.action.send")
            )
        }
    }

    private func submitOrCancel() {
        if session.isRunning {
            session.cancel()
            return
        }

        guard let provider = service as? ContextualQuestionStreaming else {
            session.failProviderUnavailable()
            return
        }

        let request = ContextualQuestionRequest(
            sourceText: result.queryText,
            translatedText: result.translatedText ?? "",
            sourceLanguage: result.from,
            targetLanguage: result.to,
            question: session.draft
        )
        session.submit(request: request, provider: provider)
    }

    private func scheduleHeightUpdate() {
        heightUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updatePreferredHeight()
        }
        heightUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func updatePreferredHeight() {
        let newHeight = calculatedHeight
        guard abs(newHeight - preferredHeight) > 0.5 else {
            needsLayout = true
            return
        }

        preferredHeight = newHeight
        needsLayout = true
        heightDidChange?(newHeight)
    }

    private func layoutContent() {
        guard session.isExpanded else { return }

        let width = max(bounds.width, contentWidth)
        actionButton.frame = NSRect(
            x: width - Layout.actionButtonWidth,
            y: 1,
            width: Layout.actionButtonWidth,
            height: Layout.actionButtonWidth
        )
        inputField.frame = NSRect(
            x: 0,
            y: 0,
            width: max(width - Layout.actionButtonWidth - 4, 80),
            height: Layout.inputHeight
        )

        var y = Layout.inputHeight
        if !session.answer.isEmpty {
            y += Layout.sectionSpacing
            answerHeader.frame = NSRect(
                x: 0,
                y: y,
                width: max(width - Layout.actionButtonWidth, 80),
                height: Layout.answerHeaderHeight
            )
            answerCopyButton.frame = NSRect(
                x: width - Layout.actionButtonWidth,
                y: y - 1,
                width: Layout.actionButtonWidth,
                height: Layout.actionButtonWidth
            )
            y += Layout.answerHeaderHeight + Layout.textSpacing
            answerLabel.frame = NSRect(x: 0, y: y, width: width, height: answerHeight)
            y += answerHeight
        }

        if !statusText.isEmpty {
            y += Layout.textSpacing
            statusLabel.frame = NSRect(x: 0, y: y, width: width, height: statusHeight)
        }
    }
}
