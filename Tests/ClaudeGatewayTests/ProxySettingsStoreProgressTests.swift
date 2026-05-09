import GatewayProxyCore
import XCTest
@testable import ClaudeGateway

@MainActor
final class ProxySettingsStoreProgressTests: XCTestCase {
    func testPersistingStateStaysTrueUntilAsyncSyncOperationCompletes() async throws {
        let configURL = try makeTemporaryConfigURL()
        let operationStarted = expectation(description: "sync operation started")
        let releaseOperation = DispatchSemaphore(value: 0)

        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        ) { _, _ in
            operationStarted.fulfill()
            _ = releaseOperation.wait(timeout: .now() + 5)

            var syncReport = ClaudeConfigSyncReport()
            syncReport.createdClaudeCodeSettings = ["test-settings.json"]
            return ProxySettingsSyncResult(
                runtimeReport: RuntimeInstallReport(),
                syncReport: syncReport,
                serviceMessage: "常驻服务已启动。"
            )
        }

        store.providers[0].baseURL = "https://provider.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-test"
        store.localGatewayKey = "sk-local-test"

        store.syncClaudeDesktopConfig()

        XCTAssertTrue(store.isPersistingAndSyncing)
        await fulfillment(of: [operationStarted], timeout: 1)
        XCTAssertTrue(store.isPersistingAndSyncing)

        releaseOperation.signal()

        let didFinish = await waitUntil {
            !store.isPersistingAndSyncing
        }

        XCTAssertTrue(didFinish)
        XCTAssertFalse(store.statusIsError)
        XCTAssertTrue(store.statusMessage.contains("常驻服务已启动"))
    }

    func testValidationFailureDoesNotLeavePersistingStateStuck() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )

        store.providers[0].baseURL = ""

        store.syncClaudeDesktopConfig()

        XCTAssertFalse(store.isPersistingAndSyncing)
        XCTAssertTrue(store.statusIsError)
        XCTAssertTrue(store.statusMessage.contains("Base URL"))
    }

    func testAddedProviderStartsWithEmptySystemPromptInjection() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )

        store.addProvider()

        XCTAssertEqual(store.providers.last?.systemPromptInjection, "")
    }

    func testDefaultSettingsAreNotSetupCompleteUntilProviderCredentialsExist() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )

        XCTAssertFalse(store.setupIsComplete)

        store.providers[0].baseURL = "https://provider.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-provider-test"
        store.localGatewayKey = "sk-local-test"

        XCTAssertTrue(store.setupIsComplete)
    }

    func testSetupCompleteRejectsInvalidLocalEndpointPort() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )
        store.providers[0].baseURL = "https://provider.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-provider-test"
        store.localGatewayKey = "sk-local-test"

        store.portText = "65536"
        XCTAssertFalse(store.localEndpointIsComplete)
        XCTAssertFalse(store.setupIsComplete)

        store.portText = "4001"
        XCTAssertTrue(store.localEndpointIsComplete)
        XCTAssertTrue(store.setupIsComplete)
    }

    func testSetupCompleteRejectsInvalidVisionBaseURL() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )
        store.providers[0].baseURL = "https://provider.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-provider-test"
        store.localGatewayKey = "sk-local-test"

        store.visionProviderBaseURL = "not-a-url"
        XCTAssertFalse(store.visionSettingsAreValid)
        XCTAssertFalse(store.setupIsComplete)

        store.visionProviderBaseURL = "https://vision.example.com/v1"
        XCTAssertTrue(store.visionSettingsAreValid)
        XCTAssertTrue(store.setupIsComplete)
    }

    func testApplyingDeepSeekProfileUsesProviderNeutralPromptPath() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )
        store.providers[0].baseURL = "https://old.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-kept"
        store.localGatewayKey = "sk-local-kept"

        store.applyCompatibilityProfile(GatewayProviderProfileCatalog.deepSeekV4ProClaudeCodeID, toProviderAt: 0)

        let provider = try XCTUnwrap(store.providers.first)
        XCTAssertEqual(GatewayProviderProfileCatalog.deepSeekV4ProClaudeCode.displayName, "DeepSeek")
        XCTAssertTrue(store.activeProviderUsesDeepSeekCompatibilityProfile)
        XCTAssertEqual(provider.baseURL, "https://api.deepseek.com/anthropic")
        XCTAssertEqual(provider.compatibilityProfileID, GatewayProviderProfileCatalog.deepSeekV4ProClaudeCodeID)
        XCTAssertTrue(provider.claudeCode.appendSystemPromptEnabled)
        XCTAssertEqual(provider.claudeCode.appendSystemPromptPath, "~/.claude/claude-gateway/claude-code.system.md")
        XCTAssertFalse(provider.claudeCode.appendSystemPromptPath.localizedCaseInsensitiveContains("deepseek"))
        XCTAssertTrue(provider.claudeCode.appendSystemPromptText.contains("You are DeepSeek-V4-Pro running inside the Claude Code agent harness."))
        XCTAssertEqual(store.defaultRouteModel, "deepseek-v4-pro[1m]")
        XCTAssertEqual(store.modelRoutes.first { $0.alias == "claude-haiku-4-5" }?.upstreamModel, "deepseek-v4-flash")
        XCTAssertEqual(store.providerAPIKeys["custom"], "sk-kept")
        XCTAssertEqual(store.localGatewayKey, "sk-local-kept")
    }

    func testRemoveModelRouteRemovesOnlySelectedIndexWhenAliasesRepeat() throws {
        let configURL = try makeTemporaryConfigURL()
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )
        store.modelRoutes = [
            .init(alias: "duplicate", providerID: "custom", upstreamModel: "first"),
            .init(alias: "duplicate", providerID: "custom", upstreamModel: "second"),
        ]

        store.removeModelRoute(at: 0)

        XCTAssertEqual(store.modelRoutes.map(\.upstreamModel), ["second"])
    }

    func testExportConfigWritesSingleFileWithSettingsAndSecrets() throws {
        let configURL = try makeTemporaryConfigURL()
        let exportURL = configURL.deletingLastPathComponent().appendingPathComponent("export.json")
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )
        store.providers[0].baseURL = "https://provider.example.com/anthropic"
        store.providerAPIKeys["custom"] = "sk-provider-test"
        store.localGatewayKey = "sk-local-test"
        store.defaultRouteModel = "provider-sonnet"
        store.modelRoutes[0].upstreamModel = "provider-opus"

        store.exportConfig(to: exportURL)

        XCTAssertFalse(store.statusIsError)
        let exported = try JSONDecoder().decode(GatewayAppConfig.self, from: Data(contentsOf: exportURL))
        XCTAssertEqual(exported.providers.first?.baseURL, "https://provider.example.com/anthropic")
        XCTAssertEqual(exported.providerSecrets["custom"]?.apiKey, "sk-provider-test")
        XCTAssertEqual(exported.localGatewayKey, "sk-local-test")
        XCTAssertEqual(exported.defaultRoute.upstreamModel, "provider-sonnet")
    }

    func testImportConfigLoadsSettingsAndSecretsFromSingleFile() throws {
        let configURL = try makeTemporaryConfigURL()
        let importURL = configURL.deletingLastPathComponent().appendingPathComponent("import.json")
        let imported = GatewayAppConfig(
            host: "127.0.0.1",
            port: 4010,
            providers: [
                GatewayProvider(
                    id: "custom",
                    displayName: "Imported Provider",
                    baseURL: "https://provider.example.com/anthropic",
                    auth: GatewayProviderAuth(type: GatewayProviderAuth.bearer)
                ),
            ],
            defaultProviderID: "custom",
            defaultRoute: GatewayRouteTarget(providerID: "custom", upstreamModel: "provider-default"),
            modelRoutes: [
                GatewayModelRoute(alias: "claude-sonnet-4-6", providerID: "custom", upstreamModel: "provider-sonnet"),
            ],
            localGatewayKey: "sk-local-imported",
            providerSecrets: ["custom": GatewayProviderSecret(apiKey: "sk-provider-imported")],
            visionProviderAPIKey: "sk-vision-imported"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(imported).write(to: importURL)
        let store = ProxySettingsStore(
            configURL: configURL,
            installRuntimeOnInit: false
        )

        store.importConfig(from: importURL)

        XCTAssertFalse(store.statusIsError)
        XCTAssertEqual(store.portText, "4010")
        XCTAssertEqual(store.providers.first?.displayName, "Imported Provider")
        XCTAssertEqual(store.providerAPIKeys["custom"], "sk-provider-imported")
        XCTAssertEqual(store.localGatewayKey, "sk-local-imported")
        XCTAssertEqual(store.visionProviderAPIKey, "sk-vision-imported")
    }

    private func makeTemporaryConfigURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeGatewayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root.appendingPathComponent("config.json")
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
