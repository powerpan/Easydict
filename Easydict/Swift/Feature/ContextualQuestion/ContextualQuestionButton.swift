//
//  ContextualQuestionButton.swift
//  Easydict
//
//  Created by Eric Pan on 2026/9/17.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import SFSafeSymbols

/// Inline result-card button that expands or collapses the contextual question panel.
/// It keeps its selected appearance synchronized with session state even when the panel
/// collapses through the keyboard rather than another mouse click.
@objc(EDContextualQuestionButton)
final class ContextualQuestionButton: EZHoverButton {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: Internal

    @objc var questionAvailable = false {
        didSet {
            isEnabled = questionAvailable
            applyVisualState()
        }
    }

    @objc
    func bind(to session: ContextualQuestionSession) {
        self.session = session
        cancellables.removeAll()

        session.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyVisualState()
            }
            .store(in: &cancellables)
    }

    // MARK: Private

    private weak var session: ContextualQuestionSession?
    private var cancellables: Set<AnyCancellable> = []

    private func configure() {
        cornerRadius = 5
        image = NSImage(systemSymbol: .questionmarkBubble)
        setAccessibilityLabel(String(localized: "contextual_question.action.ask"))

        clickBlock = { [weak self] _ in
            self?.session?.toggleExpanded()
        }

        executeOnAppearanceChange { [weak self] _, _ in
            self?.applyVisualState()
        }
    }

    private func applyVisualState() {
        let expanded = session?.isExpanded == true
        image = NSImage(
            systemSymbol: expanded ? .questionmarkBubbleFill : .questionmarkBubble
        )

        let activeColor: NSColor = isDarkMode ? .ez_imageTintDark() : .ez_imageTintLight()
        contentTintColor = questionAvailable ? activeColor : activeColor.withAlphaComponent(0.35)

        toolTip = questionAvailable
            ? String(localized: "contextual_question.action.ask")
            : String(localized: "contextual_question.action.available_after_translation")
    }
}
