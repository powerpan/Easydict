//
//  ConfigurationItemRegistryTests.swift
//  EasydictTests
//
//  Created by Eric Pan on 2026/8/26.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

/// Locks down the fail-closed configuration inventory shared by backup and URL Scheme handling.
@Suite("Configuration Item Registry", .tags(.unit))
struct ConfigurationItemRegistryTests {
    @Test("Classifies every static service credential as sensitive")
    func classifiesStaticServiceCredentials() {
        let credentialKeys = [
            "EZDeepLAuthKey",
            "EZBingCookieKey",
            "EZNiuTransAPIKey",
            "EZCaiyunToken",
            "EZTencentSecretId",
            "EZTencentSecretKey",
            "EZGeminiAPIKey",
            "EZAliAccessKeyId",
            "EZAliAccessKeySecret",
            "EZBaiduAppId",
            "EZBaiduSecretKey",
            "EZVolcanoAccessKeyID",
            "EZVolcanoSecretAccessKey",
            "EZDoubaoAPIKey",
        ]

        for key in credentialKeys {
            #expect(ConfigurationItemRegistry.category(forUserDefaultsKey: key) == .serviceCredential)
            #expect(ConfigurationItemRegistry.isSensitiveKey(key))
            #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey(key))
        }
    }

    @Test("Classifies dynamic service API keys by exact service and UUID")
    func classifiesDynamicServiceCredentials() throws {
        let service = ServiceType.customOpenAI.rawValue
        let uuid = "00000000-0000-4000-8000-000000000001"
        let key = "EZ\(service)API_\(uuid)_Key"
        let entry = try #require(ConfigurationItemRegistry.entry(forUserDefaultsKey: key))

        #expect(entry.category == .serviceCredential)
        #expect(entry.descriptor.name == "service.configuration")
        #expect(entry.descriptor.qualifiers == [
            "service": service,
            "field": ServiceConfigurationKey.apiKey.rawValue,
            "uuid": uuid,
        ])
        #expect(entry.userDefaultsKey == key)
        #expect(ConfigurationItemRegistry.entry(for: entry.descriptor)?.userDefaultsKey == key)
        #expect(!entry.isSchemeAutomatable)
    }

    @Test("Rejects malformed dynamic service descriptors and storage keys")
    func rejectsMalformedDynamicServiceItems() {
        let service = ServiceType.customOpenAI.rawValue
        let malformedKey = "EZ\(service)API_not-a-uuid_Key"
        let extraQualifier = ConfigurationItemDescriptor(
            name: "service.configuration",
            qualifiers: [
                "service": service,
                "field": ServiceConfigurationKey.apiKey.rawValue,
                "uuid": "00000000-0000-4000-8000-000000000001",
                "rawKey": "arbitrary",
            ]
        )

        #expect(ConfigurationItemRegistry.entry(forUserDefaultsKey: malformedKey) == nil)
        #expect(ConfigurationItemRegistry.category(forUserDefaultsKey: malformedKey) == .unsupported)
        #expect(ConfigurationItemRegistry.entry(for: extraQualifier) == nil)
    }

    @Test("Allows only registered non-sensitive non-endpoint URL Scheme automation")
    func allowsOnlyRegisteredNonSensitiveAutomation() {
        let service = ServiceType.customOpenAI.rawValue
        let uuid = "00000000-0000-4000-8000-000000000003"
        let endpointKeys = [
            "EZDeepLTranslateEndPointKey",
            "EZ\(service)EndPointKey",
            "EZ\(service)EndPoint_\(uuid)_Key",
        ]
        let modelKey = "EZ\(service)ModelKey"
        let promptKey = "EZ\(service)SystemPromptKey"

        #expect(ConfigurationItemRegistry.isSchemeAutomatableKey("EZBetaFeatureKey"))
        for endpointKey in endpointKeys {
            #expect(ConfigurationItemRegistry.isEndpointKey(endpointKey))
            #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey(endpointKey))
        }
        #expect(ConfigurationItemRegistry.isSchemeAutomatableKey(modelKey))
        #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey(promptKey))
        #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey("unregistered-setting"))
    }

    @Test("CLI preferences round trip while account mode rejects URL Scheme writes")
    func classifiesCLIPreferencesWithoutAutomatingAccountMode() throws {
        let service = ServiceType.codexCLI.rawValue
        let fields: [(ServiceConfigurationKey, String)] = [
            (.cliEffort, "high"),
            (.codexAccessMode, "managed"),
            (.codexManagedModel, "test-model"),
            (.codexManagedReasoningEffort, "medium"),
        ]

        for uuid in ["", "00000000-0000-4000-8000-000000000004"] {
            for (field, value) in fields {
                var qualifiers = ["service": service, "field": field.rawValue]
                if !uuid.isEmpty { qualifiers["uuid"] = uuid }
                let descriptor = ConfigurationItemDescriptor(
                    name: "service.configuration", qualifiers: qualifiers
                )
                let entry = try #require(ConfigurationItemRegistry.entry(for: descriptor))

                #expect(entry.category == .portableSetting)
                #expect(entry.accepts(value))
                #expect(!entry.accepts(NSNumber(value: true)))
                #expect(!entry.accepts(NSNumber(value: 1)))
                #expect(
                    ConfigurationItemRegistry.entry(forUserDefaultsKey: entry.userDefaultsKey)?.descriptor ==
                        descriptor
                )
                if field == .codexAccessMode {
                    #expect(!entry.isSchemeAutomatable)
                    #expect(ConfigurationItemRegistry
                        .schemeValue(forKey: entry.userDefaultsKey, rawValue: value) == nil)
                } else {
                    #expect(entry.isSchemeAutomatable)
                    #expect(
                        ConfigurationItemRegistry.schemeValue(
                            forKey: entry.userDefaultsKey,
                            rawValue: value
                        ) as? String ==
                            value
                    )
                }
            }
        }
    }

    @Test("Separates user content, runtime state, and unknown keys")
    func separatesExcludedAndUnsupportedItems() {
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "EZConfiguration_kFavorites") ==
                .excludedContent
        )
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "EZConfiguration_kQueryHistory") ==
                .excludedContent
        )
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "kQueryCharacterCountKey") ==
                .excludedRuntime
        )
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "MASPreferences Selected Identifier") ==
                .excludedRuntime
        )
        #expect(
            ConfigurationItemRegistry.category(
                forUserDefaultsKey: "inPlaceTranslationPrivacyDisclosureAcknowledged"
            ) == .excludedRuntime
        )
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "future.unregistered.key") ==
                .unsupported
        )
    }

    @Test("Backs up the vocabulary notebook toggle without restoring a machine-local directory")
    func separatesVocabularyNotebookPreferenceFromLocalDirectory() throws {
        let entry = try #require(
            ConfigurationItemRegistry.entry(forUserDefaultsKey: "enableVocabularyNotebook")
        )

        #expect(entry.category == .portableSetting)
        #expect(entry.descriptor.name == "setting.vocabulary-notebook.enabled")
        #expect(entry.accepts(NSNumber(value: true)))
        #expect(!entry.accepts(NSNumber(value: 1)))
        #expect(!entry.isSchemeAutomatable)
        #expect(ConfigurationItemRegistry.entry(for: entry.descriptor)?.userDefaultsKey == entry.userDefaultsKey)
        #expect(
            ConfigurationItemRegistry.category(forUserDefaultsKey: "vocabularyNotebookDirectory") ==
                .excludedRuntime
        )
        #expect(ConfigurationItemRegistry.entry(forUserDefaultsKey: "vocabularyNotebookDirectory") == nil)
        #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey("vocabularyNotebookDirectory"))
    }

    @Test("Anki preferences are portable but reject URL Scheme automation and runtime caches")
    func classifiesAnkiPreferencesAndRuntimeCaches() throws {
        let settings: [(String, String, ConfigurationValueKind)] = [
            ("enableAnkiConnect", "enabled", .boolean),
            ("ankiConnectEndpoint", "endpoint", .string),
            ("ankiConnectDeck", "deck", .string),
            ("ankiConnectModel", "model", .string),
            ("ankiConnectFrontField", "front-field", .string),
            ("ankiConnectBackField", "back-field", .string),
            ("ankiConnectFieldMappings", "field-mappings", .array),
        ]

        for (key, descriptorSuffix, valueKind) in settings {
            let entry = try #require(ConfigurationItemRegistry.entry(forUserDefaultsKey: key))
            #expect(entry.category == .portableSetting)
            #expect(entry.descriptor.name == "setting.anki.\(descriptorSuffix)")
            #expect(entry.allowedValueKinds == [valueKind])
            #expect(entry.isEndpoint == (key == "ankiConnectEndpoint"))
            #expect(!entry.isSchemeAutomatable)
            #expect(ConfigurationItemRegistry.schemeValue(forKey: key, rawValue: "untrusted") == nil)
            #expect(ConfigurationItemRegistry.entry(for: entry.descriptor)?.userDefaultsKey == key)
        }

        for key in ["ankiConnectModelFields", "EZDeepLWebAppVersionCacheKey"] {
            #expect(ConfigurationItemRegistry.category(forUserDefaultsKey: key) == .excludedRuntime)
            #expect(ConfigurationItemRegistry.entry(forUserDefaultsKey: key) == nil)
            #expect(!ConfigurationItemRegistry.isSchemeAutomatableKey(key))
        }
    }

    @Test("Treats the disabled-app list as a portable user setting")
    func includesDisabledAppConfiguration() throws {
        let entry = try #require(
            ConfigurationItemRegistry.entry(forUserDefaultsKey: "kAppModelTriggerListKey")
        )

        #expect(entry.category == .portableSetting)
        #expect(entry.accepts([
            [
                "appBundleID": "com.example.editor",
                "triggerType": NSNumber(value: 1),
            ],
        ]))
        #expect(!entry.isSchemeAutomatable)
    }

    @Test("Accepts only serialized Data for shortcut settings")
    func validatesShortcutStorageKind() throws {
        let entry = try #require(
            ConfigurationItemRegistry.entry(
                forUserDefaultsKey: "EZSelectionShortcutKey_keyHolder"
            )
        )

        #expect(entry.accepts(Data([0x00, 0x01, 0xFF])))
        #expect(!entry.accepts([
            "characters": "k",
            "modifiers": [1, 2, 4],
        ]))
        #expect(entry.allowedValueKinds == [.data])
    }

    @Test("Includes every in-place translation preference as a portable setting")
    func includesInPlaceTranslationPreferences() throws {
        let expectedEntries: [(key: String, name: String, value: Any)] = [
            (
                "EZInPlaceScreenshotTranslationShortcutKey_keyHolder",
                "shortcut.in-place-screenshot-translation",
                Data([0x00, 0x01, 0xFF])
            ),
            (
                "inPlaceTranslationServiceIdentifier",
                "setting.in-place-translation-service",
                "custom-openai:00000000-0000-4000-8000-000000000001"
            ),
            (
                "inPlaceTranslationLiveUpdatesEnabled",
                "setting.in-place-translation-live-updates",
                NSNumber(value: true)
            ),
            (
                "inPlaceTranslationPinned",
                "setting.in-place-translation-pinned",
                NSNumber(value: false)
            ),
        ]

        for expected in expectedEntries {
            let entry = try #require(
                ConfigurationItemRegistry.entry(forUserDefaultsKey: expected.key)
            )

            #expect(entry.category == .portableSetting)
            #expect(entry.descriptor.name == expected.name)
            #expect(entry.accepts(expected.value))
            #expect(!entry.isSchemeAutomatable)
            #expect(
                ConfigurationItemRegistry.entry(for: entry.descriptor)?.userDefaultsKey ==
                    expected.key
            )
        }
    }

    @Test("Round trips service order and instance descriptors")
    func roundTripsServiceStorageDescriptors() throws {
        let service = ServiceType.customOpenAI.rawValue
        let uuid = "00000000-0000-4000-8000-000000000002"
        let orderKey = "kAllServiceTypesKey-1"
        let instanceKey = "kServiceInfoStorageKey-\(service)-\(uuid)-1"

        for key in [orderKey, instanceKey] {
            let entry = try #require(ConfigurationItemRegistry.entry(forUserDefaultsKey: key))
            #expect(entry.category == .portableSetting)
            #expect(ConfigurationItemRegistry.entry(for: entry.descriptor)?.userDefaultsKey == key)
        }

        #expect(ConfigurationItemRegistry.entry(forUserDefaultsKey: "kAllServiceTypesKey-9") == nil)
        #expect(
            ConfigurationItemRegistry.entry(
                forUserDefaultsKey: "kServiceInfoStorageKey-\(service)-not-a-uuid-1"
            ) == nil
        )
    }

    @Test("Distinguishes property-list booleans from numeric values")
    func detectsPropertyListNumberKinds() {
        #expect(ConfigurationValueKind.detect(NSNumber(value: true)) == .boolean)
        #expect(ConfigurationValueKind.detect(NSNumber(value: 1)) == .integer)
        #expect(ConfigurationValueKind.detect(NSNumber(value: 1.5)) == .real)
    }

    @Test("Treats enum-backed UI preferences as integer raw values")
    func validatesEnumBackedIntegerSettings() throws {
        let integerKeys = [
            "EZConfiguration_kPronunciationKey",
            "EZConfiguration_kLanguageDetectOptimizeTypeKey",
            "EZConfiguration_kShowFixedWindowPositionKey",
            "EZConfiguration_kShowMiniWindowPositionKey",
            "EZConfiguration_kMouseSelectTranslateWindowTypeKey",
            "EZConfiguration_kShortcutSelectTranslateWindowTypeKey",
            "EZConfiguration_kApperanceKey",
            "EZConfiguration_kForceGetSelectedTextTypeKey",
        ]

        for key in integerKeys {
            let entry = try #require(ConfigurationItemRegistry.entry(forUserDefaultsKey: key))
            #expect(entry.category == .portableSetting)
            #expect(entry.accepts(NSNumber(value: 1)))
            #expect(!entry.accepts("1"))
            #expect(!entry.accepts(NSNumber(value: true)))
        }
    }

    @Test("Validates values using the registered storage kind")
    func validatesRegisteredValueKinds() throws {
        let integerEntry = try #require(
            ConfigurationItemRegistry.entry(forUserDefaultsKey: "maxWindowHeightPercentage")
        )
        let booleanEntry = try #require(
            ConfigurationItemRegistry.entry(forUserDefaultsKey: "EZBetaFeatureKey")
        )

        #expect(integerEntry.accepts(NSNumber(value: 1)))
        #expect(!integerEntry.accepts(NSNumber(value: true)))
        #expect(booleanEntry.accepts(NSNumber(value: true)))
        #expect(!booleanEntry.accepts(NSNumber(value: 1)))
        #expect(!integerEntry.accepts("1"))
    }
}
