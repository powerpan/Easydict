//
//  Configuration+UserData.swift
//  Easydict
//
//  Created by ljk on 2024/1/17.
//  Copyright © 2024 izual. All rights reserved.
//

import Foundation

extension MyConfiguration {
    @MainActor
    func resetUserDefaultsData() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        CodexRequestCoordinator.shared.reset()
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }
}
