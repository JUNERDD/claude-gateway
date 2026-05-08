import Foundation

public enum GatewayConfigurationDefaults {
    public static let providerID = "custom"
    public static let providerName = "Custom Anthropic-compatible"
    public static let routeAliases = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5",
    ]

    public static var provider: GatewayProvider {
        GatewayProvider(
            id: providerID,
            displayName: providerName,
            baseURL: "",
            auth: GatewayProviderAuth(type: GatewayProviderAuth.xAPIKey),
            defaultHeaders: [:]
        )
    }

    public static var routeTarget: GatewayRouteTarget {
        GatewayRouteTarget(providerID: providerID, upstreamModel: routeAliases[1])
    }

    public static var modelRoutes: [GatewayModelRoute] {
        routeAliases.map {
            GatewayModelRoute(alias: $0, providerID: providerID, upstreamModel: $0)
        }
    }
}

public struct GatewayProviderAuth: Codable, Equatable, Hashable {
    public static let xAPIKey = "x-api-key"
    public static let bearer = "bearer"
    public static let none = "none"
    public static let customHeader = "custom-header"
    public static let supportedTypes = [xAPIKey, bearer, none, customHeader]

    public var type: String
    public var customHeaderName: String

    public init(type: String = GatewayProviderAuth.xAPIKey, customHeaderName: String = "") {
        self.type = Self.normalizedType(type)
        self.customHeaderName = customHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedType(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedTypes.contains(cleaned) ? cleaned : xAPIKey
    }

    public var requiresAPIKey: Bool {
        type != Self.none
    }
}

public struct GatewayProvider: Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var baseURL: String
    public var auth: GatewayProviderAuth
    public var defaultHeaders: [String: String]

    public init(
        id: String,
        displayName: String,
        baseURL: String,
        auth: GatewayProviderAuth = GatewayProviderAuth(),
        defaultHeaders: [String: String] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.auth = auth
        self.defaultHeaders = defaultHeaders
    }

    public var nameForDisplay: String {
        displayName.isEmpty ? id : displayName
    }

    public static let gatewayManagedHeaders: Set<String> = [
        "accept",
        "anthropic-beta",
        "anthropic-version",
        "connection",
        "content-length",
        "content-type",
        "host",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "user-agent",
    ]

    public func sanitizedDefaultHeaders() -> [String: String] {
        defaultHeaders.reduce(into: [:]) { result, item in
            let name = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { return }
            guard !Self.gatewayManagedHeaders.contains(name.lowercased()) else { return }
            result[name] = value
        }
    }
}

public struct GatewayRouteTarget: Codable, Equatable {
    public var providerID: String
    public var upstreamModel: String

    public init(providerID: String, upstreamModel: String) {
        self.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.upstreamModel = upstreamModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GatewayModelRoute: Codable, Equatable, Identifiable {
    public var alias: String
    public var providerID: String
    public var upstreamModel: String

    public var id: String { alias }

    public init(alias: String, providerID: String, upstreamModel: String) {
        self.alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.upstreamModel = upstreamModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var target: GatewayRouteTarget {
        GatewayRouteTarget(providerID: providerID, upstreamModel: upstreamModel)
    }
}

public struct GatewayProviderSecret: Codable, Equatable {
    public var apiKey: String

    public init(apiKey: String = "") {
        self.apiKey = apiKey
    }
}

public struct GatewaySecrets: Codable, Equatable {
    public var localGatewayKey: String
    public var providerSecrets: [String: GatewayProviderSecret]
    public var visionProviderAPIKey: String

    public init(
        localGatewayKey: String = "",
        providerSecrets: [String: GatewayProviderSecret] = [:],
        visionProviderAPIKey: String = ""
    ) {
        self.localGatewayKey = localGatewayKey
        self.providerSecrets = providerSecrets
        self.visionProviderAPIKey = visionProviderAPIKey
    }
}
