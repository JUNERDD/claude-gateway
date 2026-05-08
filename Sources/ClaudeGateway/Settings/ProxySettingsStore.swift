import Foundation
import GatewayProxyCore
import SwiftUI

struct ProxySettingsSyncResult {
    var runtimeReport: RuntimeInstallReport
    var syncReport: ClaudeConfigSyncReport
    var serviceMessage: String
}

@MainActor
final class ProxySettingsStore: ObservableObject {
    @Published var host: String = ProxyDiskSettings.defaults.host
    @Published var portText: String = String(ProxyDiskSettings.defaults.port)
    @Published var providers: [GatewayProvider] = ProxyDiskSettings.defaults.providers
    @Published var providerAPIKeys: [String: String] = [:]
    @Published var defaultProviderID: String = ProxyDiskSettings.defaults.defaultProviderID
    @Published var defaultRouteProviderID: String = ProxyDiskSettings.defaults.defaultRoute.providerID
    @Published var defaultRouteModel: String = ProxyDiskSettings.defaults.defaultRoute.upstreamModel
    @Published var modelRoutes: [GatewayModelRoute] = ProxyDiskSettings.defaults.modelRoutes
    @Published var visionProvider: String = ProxyDiskSettings.defaults.visionProvider
    @Published var visionProviderModel: String = ProxyDiskSettings.defaults.visionProviderModel
    @Published var visionProviderBaseURL: String = ProxyDiskSettings.defaults.visionProviderBaseURL
    @Published var systemPromptPrefix: String = ProxyDiskSettings.defaults.systemPromptPrefix
    @Published var systemPromptSuffix: String = ProxyDiskSettings.defaults.systemPromptSuffix
    @Published var visionProviderAPIKey: String = ""
    @Published var localGatewayKey: String = ""
    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false
    @Published var runtimeStatusMessage: String = ""
    @Published var runtimeStatusIsError: Bool = false
    @Published var claudeSyncStatusMessage: String = ""
    @Published var claudeSyncStatusIsError: Bool = false
    @Published private(set) var isPersistingAndSyncing: Bool = false

    private let configURL: URL
    private let secretsURL: URL
    private let persistAndSyncOperation: (ProxyDiskSettings, String) throws -> ProxySettingsSyncResult
    private var runtimeInstallTask: Task<Void, Never>?
    private var persistAndSyncTask: Task<Void, Never>?
    private var operationGeneration = 0

    init(
        configURL: URL = BundledRuntimeInstaller.settingsURL,
        secretsURL: URL = BundledRuntimeInstaller.secretsURL,
        installRuntimeOnInit: Bool = true,
        persistAndSyncOperation: @escaping (ProxyDiskSettings, String) throws -> ProxySettingsSyncResult = ProxySettingsStore.defaultPersistAndSyncOperation
    ) {
        self.configURL = configURL
        self.secretsURL = secretsURL
        self.persistAndSyncOperation = persistAndSyncOperation
        load()
        if installRuntimeOnInit {
            installBundledRuntime()
        }
    }

    private nonisolated static func defaultPersistAndSyncOperation(settings: ProxyDiskSettings, localGatewayKey: String) throws -> ProxySettingsSyncResult {
        let runtimeReport = try BundledRuntimeInstaller.installOrRepair()
        let syncReport = ClaudeDesktopConfigSync.sync(settings: settings, localGatewayKey: localGatewayKey)
        let serviceMessage = try LaunchAgentManager.start()
        return ProxySettingsSyncResult(
            runtimeReport: runtimeReport,
            syncReport: syncReport,
            serviceMessage: serviceMessage
        )
    }

    var configPathForDisplay: String {
        abbreviateHome(configURL.path)
    }

    var secretsPathForDisplay: String {
        abbreviateHome(secretsURL.path)
    }

    var advertisedModels: [String] {
        uniqueNonEmpty(modelRoutes.map(\.alias))
    }

    var primaryProvider: GatewayProvider? {
        providers.first { $0.id == defaultProviderID } ?? providers.first
    }

    var primaryProviderBaseURL: String {
        primaryProvider?.baseURL ?? ""
    }

    var defaultTargetDescription: String {
        "\(defaultRouteProviderID) / \(defaultRouteModel)"
    }

    var providerCredentialsReady: Bool {
        providers.allSatisfy { provider in
            guard provider.auth.requiresAPIKey else { return true }
            return !(providerAPIKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var claudeConfigSnippet: String {
        let payload: [String: Any] = [
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": "http://\(hostTrimmed):\(portText.trimmingCharacters(in: .whitespacesAndNewlines))",
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayApiKey": localGatewayKey,
            "inferenceModels": advertisedModels,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    func load() {
        let disk = readDiskSettings()
        host = disk.host
        portText = String(disk.port)
        providers = disk.providers
        defaultProviderID = disk.defaultProviderID
        defaultRouteProviderID = disk.defaultRoute.providerID
        defaultRouteModel = disk.defaultRoute.upstreamModel
        modelRoutes = disk.modelRoutes
        visionProvider = disk.visionProvider
        visionProviderModel = disk.visionProviderModel
        visionProviderBaseURL = disk.visionProviderBaseURL
        systemPromptPrefix = disk.systemPromptPrefix
        systemPromptSuffix = disk.systemPromptSuffix

        let secrets = readSecrets()
        localGatewayKey = secrets.localGatewayKey.isEmpty ? BundledRuntimeInstaller.generateLocalGatewayKey() : secrets.localGatewayKey
        providerAPIKeys = secrets.providerSecrets.mapValues(\.apiKey)
        visionProviderAPIKey = secrets.visionProviderAPIKey
        statusMessage = ""
        statusIsError = false
        claudeSyncStatusMessage = ""
        claudeSyncStatusIsError = false
    }

    func save() {
        persistSettingsAndSync(successPrefix: "已保存。")
    }

    func syncClaudeDesktopConfig() {
        persistSettingsAndSync(successPrefix: "已同步 Claude 配置。")
    }

    func dismissStatusMessage() {
        statusMessage = ""
        statusIsError = false
    }

    func addProvider() {
        var index = providers.count + 1
        var id = "provider-\(index)"
        while providers.contains(where: { $0.id == id }) {
            index += 1
            id = "provider-\(index)"
        }
        providers.append(GatewayProvider(
            id: id,
            displayName: "Provider \(index)",
            baseURL: "",
            auth: GatewayProviderAuth(type: GatewayProviderAuth.xAPIKey),
            defaultHeaders: [:]
        ))
    }

    func removeProvider(id: String) {
        guard providers.count > 1 else { return }
        providers.removeAll { $0.id == id }
        providerAPIKeys[id] = nil
        if defaultProviderID == id {
            defaultProviderID = providers.first?.id ?? GatewayConfigurationDefaults.providerID
        }
        if defaultRouteProviderID == id {
            defaultRouteProviderID = defaultProviderID
        }
        modelRoutes.removeAll { $0.providerID == id }
    }

    func addModelRoute() {
        let providerID = providers.first?.id ?? GatewayConfigurationDefaults.providerID
        modelRoutes.append(GatewayModelRoute(alias: "claude-custom-\(modelRoutes.count + 1)", providerID: providerID, upstreamModel: "upstream-model"))
    }

    func removeModelRoute(alias: String) {
        modelRoutes.removeAll { $0.alias == alias }
    }

    func bindingForProviderAPIKey(_ providerID: String) -> Binding<String> {
        Binding(
            get: { self.providerAPIKeys[providerID] ?? "" },
            set: { self.providerAPIKeys[providerID] = $0 }
        )
    }

    func bindingForProviderHeaders(_ providerID: String) -> Binding<String> {
        Binding(
            get: {
                guard let provider = self.providers.first(where: { $0.id == providerID }) else { return "" }
                return provider.defaultHeaders
                    .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "\n")
            },
            set: { text in
                guard let index = self.providers.firstIndex(where: { $0.id == providerID }) else { return }
                self.providers[index].defaultHeaders = Self.parseHeadersText(text)
            }
        )
    }

    private func persistSettingsAndSync(successPrefix: String) {
        do {
            if localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
            }
            let settings = try validatedDiskSettings()
            try ensureConfigDirectory()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: configURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

            let secrets = GatewaySecrets(
                localGatewayKey: localGatewayKey,
                providerSecrets: providerAPIKeys.reduce(into: [:]) { result, item in
                    result[item.key] = GatewayProviderSecret(apiKey: item.value)
                },
                visionProviderAPIKey: visionProviderAPIKey
            )
            let secretsData = try encoder.encode(secrets)
            try secretsData.write(to: secretsURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)

            let key = localGatewayKey
            let operation = persistAndSyncOperation
            operationGeneration += 1
            let generation = operationGeneration
            persistAndSyncTask?.cancel()
            isPersistingAndSyncing = true
            persistAndSyncTask = Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    try operation(settings, key)
                }.result

                guard let self, self.operationGeneration == generation else { return }
                defer {
                    self.isPersistingAndSyncing = false
                    self.persistAndSyncTask = nil
                }
                switch result {
                case let .success(result):
                    let runtimeReport = result.runtimeReport
                    let syncReport = result.syncReport
                    let serviceMessage = result.serviceMessage
                    self.statusMessage = "\(successPrefix)\(runtimeReport.userMessage) \(syncReport.userMessage) \(serviceMessage)"
                    self.statusIsError = false
                    self.claudeSyncStatusMessage = """
                    Runtime:
                      \(runtimeReport.userMessage)
                    \(syncReport.detailMessage)
                    LaunchAgent:
                      \(serviceMessage)
                    """
                    self.claudeSyncStatusIsError = !runtimeReport.warnings.isEmpty || !syncReport.warnings.isEmpty
                case let .failure(error):
                    self.statusMessage = "操作失败：\(error.localizedDescription)"
                    self.statusIsError = true
                    self.claudeSyncStatusMessage = self.statusMessage
                    self.claudeSyncStatusIsError = true
                }
            }
        } catch {
            operationGeneration += 1
            persistAndSyncTask?.cancel()
            persistAndSyncTask = nil
            isPersistingAndSyncing = false
            statusMessage = "操作失败：\(error.localizedDescription)"
            statusIsError = true
            claudeSyncStatusMessage = statusMessage
            claudeSyncStatusIsError = true
        }
    }

    func installBundledRuntime(reloadSettingsAfterInstall: Bool = false) {
        runtimeInstallTask?.cancel()
        runtimeInstallTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                try BundledRuntimeInstaller.installOrRepair()
            }.result

            guard let self else { return }
            switch result {
            case let .success(report):
                self.runtimeStatusMessage = report.userMessage
                self.runtimeStatusIsError = !report.warnings.isEmpty
                if reloadSettingsAfterInstall {
                    self.load()
                }
            case let .failure(error):
                self.runtimeStatusMessage = "运行时安装失败：\(error.localizedDescription)"
                self.runtimeStatusIsError = true
            }
            self.runtimeInstallTask = nil
        }
    }

    func resetModelDefaults() {
        modelRoutes = ProxyDiskSettings.defaultModelRoutes
        defaultProviderID = GatewayConfigurationDefaults.providerID
        defaultRouteProviderID = GatewayConfigurationDefaults.providerID
        defaultRouteModel = GatewayConfigurationDefaults.routeTarget.upstreamModel
    }

    func generateLocalGatewayKey() {
        localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
    }

    private var hostTrimmed: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedDiskSettings() throws -> ProxyDiskSettings {
        let cleanHost = hostTrimmed
        guard !cleanHost.isEmpty else { throw ProxySettingsError.emptyField("监听地址") }

        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...65535).contains(port)
        else {
            throw ProxySettingsError.invalidPort
        }

        let cleanProviders = try validatedProviders()
        let providerIDs = Set(cleanProviders.map(\.id))
        let cleanDefaultProviderID = defaultProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard providerIDs.contains(cleanDefaultProviderID) else {
            throw ProxySettingsError.invalidProviderID(cleanDefaultProviderID)
        }

        let cleanDefaultRoute = GatewayRouteTarget(
            providerID: defaultRouteProviderID,
            upstreamModel: defaultRouteModel
        )
        guard providerIDs.contains(cleanDefaultRoute.providerID) else {
            throw ProxySettingsError.invalidProviderID(cleanDefaultRoute.providerID)
        }
        guard !cleanDefaultRoute.upstreamModel.isEmpty else {
            throw ProxySettingsError.emptyField("默认上游模型")
        }

        let cleanRoutes = try validatedModelRoutes(providerIDs: providerIDs)
        guard !cleanRoutes.isEmpty else { throw ProxySettingsError.emptyModels }

        let cleanVisionProvider = ProxyDiskSettings.normalizedVisionProvider(visionProvider)
        guard cleanVisionProvider == visionProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            throw ProxySettingsError.invalidVisionProvider
        }
        let cleanVisionModel = visionProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVisionBaseURL = visionProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleanVisionBaseURL.isEmpty {
            guard validHTTPURL(cleanVisionBaseURL) else {
                throw ProxySettingsError.invalidVisionProviderBaseURL
            }
        }

        return ProxyDiskSettings(
            host: cleanHost,
            port: port,
            providers: cleanProviders,
            defaultProviderID: cleanDefaultProviderID,
            defaultRoute: cleanDefaultRoute,
            modelRoutes: cleanRoutes,
            visionProvider: cleanVisionProvider,
            visionProviderModel: cleanVisionModel,
            visionProviderBaseURL: cleanVisionBaseURL,
            systemPromptPrefix: systemPromptPrefix,
            systemPromptSuffix: systemPromptSuffix
        )
    }

    private func validatedProviders() throws -> [GatewayProvider] {
        var seen = Set<String>()
        return try providers.map { provider in
            let id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { throw ProxySettingsError.invalidProviderID(id) }
            seen.insert(id)
            let displayName = provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !baseURL.isEmpty else { throw ProxySettingsError.emptyField("\(displayName.isEmpty ? id : displayName) Base URL") }
            guard validHTTPURL(baseURL) else { throw ProxySettingsError.invalidURL("\(displayName.isEmpty ? id : displayName) Base URL") }
            let authType = GatewayProviderAuth.normalizedType(provider.auth.type)
            guard authType == provider.auth.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                throw ProxySettingsError.invalidProviderAuth(displayName.isEmpty ? id : displayName)
            }
            if authType == GatewayProviderAuth.customHeader {
                let header = provider.auth.customHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !header.isEmpty, !GatewayProvider.gatewayManagedHeaders.contains(header.lowercased()) else {
                    throw ProxySettingsError.invalidProviderHeader(displayName.isEmpty ? id : displayName)
                }
            }
            for name in provider.defaultHeaders.keys {
                guard !GatewayProvider.gatewayManagedHeaders.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                    throw ProxySettingsError.invalidProviderHeader(displayName.isEmpty ? id : displayName)
                }
            }
            if GatewayProviderAuth(type: authType).requiresAPIKey {
                let apiKey = providerAPIKeys[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !apiKey.isEmpty else { throw ProxySettingsError.emptyField("\(displayName.isEmpty ? id : displayName) API Key") }
            }
            return GatewayProvider(
                id: id,
                displayName: displayName.isEmpty ? id : displayName,
                baseURL: baseURL,
                auth: GatewayProviderAuth(type: authType, customHeaderName: provider.auth.customHeaderName),
                defaultHeaders: provider.defaultHeaders
            )
        }
    }

    private func validatedModelRoutes(providerIDs: Set<String>) throws -> [GatewayModelRoute] {
        var seen = Set<String>()
        return try modelRoutes.map { route in
            let alias = route.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerID = route.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            let upstreamModel = route.upstreamModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty else { throw ProxySettingsError.emptyField("Claude-visible 模型名") }
            guard !seen.contains(alias) else { throw ProxySettingsError.emptyField("重复模型名 \(alias)") }
            seen.insert(alias)
            guard providerIDs.contains(providerID) else { throw ProxySettingsError.invalidProviderID(providerID) }
            guard !upstreamModel.isEmpty else { throw ProxySettingsError.emptyField("\(alias) 上游模型") }
            return GatewayModelRoute(alias: alias, providerID: providerID, upstreamModel: upstreamModel)
        }
    }

    private func readDiskSettings() -> ProxyDiskSettings {
        guard let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(ProxyDiskSettings.self, from: data)
        else {
            return .defaults
        }
        return ProxyDiskSettings(
            host: decoded.host.isEmpty ? ProxyDiskSettings.defaults.host : decoded.host,
            port: decoded.port,
            providers: decoded.providers.isEmpty ? ProxyDiskSettings.defaults.providers : decoded.providers,
            defaultProviderID: decoded.defaultProviderID.isEmpty ? ProxyDiskSettings.defaults.defaultProviderID : decoded.defaultProviderID,
            defaultRoute: decoded.defaultRoute.providerID.isEmpty ? ProxyDiskSettings.defaults.defaultRoute : decoded.defaultRoute,
            modelRoutes: decoded.modelRoutes.isEmpty ? ProxyDiskSettings.defaultModelRoutes : decoded.modelRoutes,
            visionProvider: decoded.visionProvider,
            visionProviderModel: decoded.visionProviderModel.trimmingCharacters(in: .whitespacesAndNewlines),
            visionProviderBaseURL: decoded.visionProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPromptPrefix: decoded.systemPromptPrefix,
            systemPromptSuffix: decoded.systemPromptSuffix
        )
    }

    private func readSecrets() -> GatewaySecrets {
        guard let data = try? Data(contentsOf: secretsURL),
            let decoded = try? JSONDecoder().decode(GatewaySecrets.self, from: data)
        else {
            return GatewaySecrets()
        }
        return decoded
    }

    private func ensureConfigDirectory() throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }

    private func validHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return false
        }
        return true
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private static func parseHeadersText(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }
            result[name] = value
        }
        return result
    }
}
