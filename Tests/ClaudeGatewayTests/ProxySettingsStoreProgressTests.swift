import XCTest
@testable import ClaudeGateway

@MainActor
final class ProxySettingsStoreProgressTests: XCTestCase {
    func testPersistingStateStaysTrueUntilAsyncSyncOperationCompletes() async throws {
        let urls = try makeTemporaryStoreURLs()
        let operationStarted = expectation(description: "sync operation started")
        let releaseOperation = DispatchSemaphore(value: 0)

        let store = ProxySettingsStore(
            configURL: urls.config,
            secretsURL: urls.secrets,
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
        let urls = try makeTemporaryStoreURLs()
        let store = ProxySettingsStore(
            configURL: urls.config,
            secretsURL: urls.secrets,
            installRuntimeOnInit: false
        )

        store.providers[0].baseURL = ""

        store.syncClaudeDesktopConfig()

        XCTAssertFalse(store.isPersistingAndSyncing)
        XCTAssertTrue(store.statusIsError)
        XCTAssertTrue(store.statusMessage.contains("Base URL"))
    }

    func testAddedProviderStartsWithEmptySystemPromptInjection() throws {
        let urls = try makeTemporaryStoreURLs()
        let store = ProxySettingsStore(
            configURL: urls.config,
            secretsURL: urls.secrets,
            installRuntimeOnInit: false
        )

        store.addProvider()

        XCTAssertEqual(store.providers.last?.systemPromptInjection, "")
    }

    private func makeTemporaryStoreURLs() throws -> (config: URL, secrets: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeGatewayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (
            config: root.appendingPathComponent("proxy_settings.json"),
            secrets: root.appendingPathComponent("secrets.json")
        )
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
