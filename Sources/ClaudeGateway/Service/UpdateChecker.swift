import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var errorMessage: String?
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }
    @Published var lastCheckDate: Date? {
        didSet { UserDefaults.standard.set(lastCheckDate, forKey: Self.lastCheckKey) }
    }

    var isUpdateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        guard let current = currentVersion else { return false }
        return compareVersions(latest, current) > 0
    }

    private let repoOwner = "JUNERDD"
    private let repoName = "claude-gateway"

    private static let autoCheckKey = "UpdateChecker.autoCheckEnabled"
    private static let lastCheckKey = "UpdateChecker.lastCheckDate"

    init() {
        autoCheckEnabled = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
        lastCheckDate = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let tag = try await fetchLatestReleaseTag()
            latestVersion = tag
            lastCheckDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchLatestReleaseTag() async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            throw UpdateCheckError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.badResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateCheckError.httpStatus(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String
        else {
            throw UpdateCheckError.parseFailure
        }

        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard !version.isEmpty else { throw UpdateCheckError.parseFailure }
        return version
    }

    private var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxLength = max(aParts.count, bParts.count)

        for i in 0..<maxLength {
            let aValue = i < aParts.count ? aParts[i] : 0
            let bValue = i < bParts.count ? bParts[i] : 0
            if aValue != bValue { return aValue - bValue }
        }
        return 0
    }
}

enum UpdateCheckError: LocalizedError {
    case invalidURL
    case badResponse
    case httpStatus(Int)
    case parseFailure

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid update check URL"
        case .badResponse: return "No response from GitHub"
        case .httpStatus(let code): return "GitHub returned status \(code)"
        case .parseFailure: return "Could not parse release info"
        }
    }
}
