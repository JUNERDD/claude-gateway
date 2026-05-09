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
    private let persistAndSyncOperation: (ProxyDiskSettings, String) throws -> ProxySettingsSyncResult
    private var runtimeInstallTask: Task<Void, Never>?
    private var persistAndSyncTask: Task<Void, Never>?
    private var operationGeneration = 0

    init(
        configURL: URL = BundledRuntimeInstaller.configURL,
        installRuntimeOnInit: Bool = true,
        persistAndSyncOperation: @escaping (ProxyDiskSettings, String) throws -> ProxySettingsSyncResult = ProxySettingsStore.defaultPersistAndSyncOperation
    ) {
        self.configURL = configURL
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

    var advertisedModels: [String] {
        uniqueNonEmpty(modelRoutes.map(\.alias))
    }

    var primaryProvider: GatewayProvider? {
        providers.first { $0.id == defaultProviderID } ?? providers.first
    }

    var primaryProviderBaseURL: String {
        primaryProvider?.baseURL ?? ""
    }

    var activeClaudeCodeProvider: GatewayProvider? {
        providers.first { $0.id == defaultRouteProviderID }
            ?? providers.first { $0.id == defaultProviderID }
            ?? providers.first
    }

    var claudeCodeAppendPromptCommand: String {
        let path = activeClaudeCodeProvider?.claudeCode.appendSystemPromptPath
            ?? GatewayProviderClaudeCodeSettings.defaultAppendSystemPromptPath
        return ClaudeCodePromptInstaller.appendPromptCommand(displayPath: path)
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

    var setupIsComplete: Bool {
        guard localEndpointIsComplete else { return false }
        guard !localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard providersAreComplete else { return false }
        guard modelRoutesAreComplete else { return false }
        guard visionSettingsAreValid else { return false }
        return true
    }

    var localEndpointIsComplete: Bool {
        let hostValue = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portValue = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostValue.isEmpty,
            let port = Int(portValue),
            (1...65535).contains(port)
        else {
            return false
        }
        return true
    }

    var activeProviderUsesDeepSeekCompatibilityProfile: Bool {
        activeClaudeCodeProvider?.compatibilityProfileID == GatewayProviderProfileCatalog.deepSeekV4ProClaudeCodeID
    }

    var visionSettingsAreValid: Bool {
        let cleanedProvider = visionProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ProxyDiskSettings.supportedVisionProviders.contains(cleanedProvider) else { return false }
        let baseURL = visionProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseURL.isEmpty || validHTTPURL(baseURL)
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
        applyConfig(readConfig())
        statusMessage = ""
        statusIsError = false
        claudeSyncStatusMessage = ""
        claudeSyncStatusIsError = false
    }

    func importConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var config = try JSONDecoder().decode(GatewayAppConfig.self, from: data)
            if config.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
            }
            if config.providerSecrets[GatewayConfigurationDefaults.providerID] == nil {
                config.providerSecrets[GatewayConfigurationDefaults.providerID] = GatewayProviderSecret(apiKey: "")
            }
            try ensureConfigDirectory()
            try writeConfig(config)
            applyConfig(config)
            statusMessage = "已导入配置。"
            statusIsError = false
            claudeSyncStatusMessage = ""
            claudeSyncStatusIsError = false
        } catch {
            statusMessage = "导入失败：\(error.localizedDescription)"
            statusIsError = true
        }
    }

    func exportConfig(to url: URL) {
        do {
            if localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
            }
            let settings = try validatedDiskSettings()
            try writeConfig(config(settings: settings))
            if configURL.standardizedFileURL.path != url.standardizedFileURL.path {
                try FileManager.default.copyItemReplacingExisting(at: configURL, to: url)
            }
            statusMessage = "已导出配置。"
            statusIsError = false
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
            statusIsError = true
        }
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

    func removeModelRoute(at index: Int) {
        guard modelRoutes.indices.contains(index) else { return }
        modelRoutes.remove(at: index)
    }

    func applyCompatibilityProfile(_ profileID: String, toProviderAt index: Int) {
        guard providers.indices.contains(index) else { return }
        let profile = GatewayProviderProfileCatalog.profile(id: profileID)
        let providerID = providers[index].id

        providers[index].compatibilityProfileID = profile.id
        providers[index].anthropicBetaHeaderMode = profile.recommendedAnthropicBetaHeaderMode
        providers[index].claudeCode = profile.recommendedClaudeCode
        if !profile.recommendedBaseURL.isEmpty {
            providers[index].baseURL = profile.recommendedBaseURL
        }
        providers[index].auth = profile.recommendedAuth

        guard !profile.recommendedDefaultRouteModel.isEmpty else { return }
        defaultProviderID = providerID
        defaultRouteProviderID = providerID
        defaultRouteModel = profile.recommendedDefaultRouteModel
        modelRoutes = profile.recommendedModelRoutes.map { route in
            GatewayModelRoute(
                alias: route.alias,
                providerID: providerID,
                upstreamModel: route.upstreamModel
            )
        }
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
            try writeConfig(config(settings: settings))

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
            visionProviderBaseURL: cleanVisionBaseURL
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
                defaultHeaders: provider.defaultHeaders,
                systemPromptInjection: provider.systemPromptInjection,
                compatibilityProfileID: provider.compatibilityProfileID,
                anthropicBetaHeaderMode: provider.anthropicBetaHeaderMode,
                claudeCode: provider.claudeCode
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

    private func readConfig() -> GatewayAppConfig {
        guard let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(GatewayAppConfig.self, from: data)
        else { return defaultConfig() }
        return decoded
    }

    private func applyConfig(_ config: GatewayAppConfig) {
        let disk = diskSettings(from: config)
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
        localGatewayKey = config.localGatewayKey.isEmpty ? BundledRuntimeInstaller.generateLocalGatewayKey() : config.localGatewayKey
        providerAPIKeys = config.providerSecrets.mapValues(\.apiKey)
        visionProviderAPIKey = config.visionProviderAPIKey
    }

    private func diskSettings(from config: GatewayAppConfig) -> ProxyDiskSettings {
        return ProxyDiskSettings(
            host: config.host.isEmpty ? ProxyDiskSettings.defaults.host : config.host,
            port: config.port,
            providers: config.providers.isEmpty ? ProxyDiskSettings.defaults.providers : config.providers,
            defaultProviderID: config.defaultProviderID.isEmpty ? ProxyDiskSettings.defaults.defaultProviderID : config.defaultProviderID,
            defaultRoute: config.defaultRoute.providerID.isEmpty ? ProxyDiskSettings.defaults.defaultRoute : config.defaultRoute,
            modelRoutes: config.modelRoutes.isEmpty ? ProxyDiskSettings.defaultModelRoutes : config.modelRoutes,
            visionProvider: config.visionProvider,
            visionProviderModel: config.visionProviderModel.trimmingCharacters(in: .whitespacesAndNewlines),
            visionProviderBaseURL: config.visionProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func defaultConfig() -> GatewayAppConfig {
        GatewayAppConfig(
            host: ProxyDiskSettings.defaults.host,
            port: ProxyDiskSettings.defaults.port,
            providers: ProxyDiskSettings.defaults.providers,
            defaultProviderID: ProxyDiskSettings.defaults.defaultProviderID,
            defaultRoute: ProxyDiskSettings.defaults.defaultRoute,
            modelRoutes: ProxyDiskSettings.defaults.modelRoutes,
            visionProvider: ProxyDiskSettings.defaults.visionProvider,
            visionProviderModel: ProxyDiskSettings.defaults.visionProviderModel,
            visionProviderBaseURL: ProxyDiskSettings.defaults.visionProviderBaseURL,
            localGatewayKey: BundledRuntimeInstaller.generateLocalGatewayKey(),
            providerSecrets: [
                GatewayConfigurationDefaults.providerID: GatewayProviderSecret(apiKey: ""),
            ],
            visionProviderAPIKey: ""
        )
    }

    private func config(settings: ProxyDiskSettings) -> GatewayAppConfig {
        GatewayAppConfig(
            host: settings.host,
            port: settings.port,
            providers: settings.providers,
            defaultProviderID: settings.defaultProviderID,
            defaultRoute: settings.defaultRoute,
            modelRoutes: settings.modelRoutes,
            visionProvider: settings.visionProvider,
            visionProviderModel: settings.visionProviderModel,
            visionProviderBaseURL: settings.visionProviderBaseURL,
            localGatewayKey: localGatewayKey,
            providerSecrets: providerAPIKeys.reduce(into: [:]) { result, item in
                result[item.key] = GatewayProviderSecret(apiKey: item.value)
            },
            visionProviderAPIKey: visionProviderAPIKey
        )
    }

    private func writeConfig(_ config: GatewayAppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
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

    private var providersAreComplete: Bool {
        guard !providers.isEmpty else { return false }
        var seenIDs = Set<String>()
        for provider in providers {
            let id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seenIDs.contains(id) else { return false }
            seenIDs.insert(id)

            guard validHTTPURL(provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            if provider.auth.type == GatewayProviderAuth.customHeader {
                let header = provider.auth.customHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !header.isEmpty, !GatewayProvider.gatewayManagedHeaders.contains(header.lowercased()) else { return false }
            }
            if provider.auth.requiresAPIKey {
                let apiKey = providerAPIKeys[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !apiKey.isEmpty else { return false }
            }
        }
        return true
    }

    private var modelRoutesAreComplete: Bool {
        let providerIDs = Set(providers.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard providerIDs.contains(defaultRouteProviderID) else { return false }
        guard !defaultRouteModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !modelRoutes.isEmpty else { return false }

        var aliases = Set<String>()
        for route in modelRoutes {
            let alias = route.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let upstreamModel = route.upstreamModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerID = route.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, !upstreamModel.isEmpty, providerIDs.contains(providerID), !aliases.contains(alias) else {
                return false
            }
            aliases.insert(alias)
        }
        return true
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

private extension FileManager {
    func copyItemReplacingExisting(at sourceURL: URL, to destinationURL: URL) throws {
        if fileExists(atPath: destinationURL.path) {
            try removeItem(at: destinationURL)
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }
}
