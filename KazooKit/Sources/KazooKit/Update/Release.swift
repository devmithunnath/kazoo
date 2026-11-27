import Foundation

/// A dotted numeric version such as "0.1.1" (a leading "v" is ignored). Missing parts compare as zero.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]
    public let description: String

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        // Ignore build metadata or pre-release suffixes ("1.2.0-beta" compares as 1.2.0).
        let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.components = parts.compactMap { $0 }
        self.description = core
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The newest published Kazoo release.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: String
    public let tag: String
    public let pageURL: URL
    public let downloadURL: URL?
    public let notes: String?
    public let publishedAt: Date?

    public init(version: String, tag: String, pageURL: URL, downloadURL: URL?, notes: String?, publishedAt: Date?) {
        self.version = version
        self.tag = tag
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.notes = notes
        self.publishedAt = publishedAt
    }
}

public enum UpdateCheckError: Error, Equatable, LocalizedError {
    case offline
    case rateLimited
    case noRelease
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .offline: "Couldn’t reach GitHub. Check your connection and try again."
        case .rateLimited: "GitHub is limiting update checks right now. Try again in a little while."
        case .noRelease: "No published release was found."
        case .invalidResponse: "GitHub returned an unexpected response."
        }
    }
}

public protocol ReleaseFetching: Sendable {
    func latestRelease() async throws(UpdateCheckError) -> ReleaseInfo
}

/// Reads `releases/latest` from the public GitHub API (no token; drafts and pre-releases are excluded by GitHub).
public struct GitHubReleaseFetcher: ReleaseFetching {
    public static let repository = "devmithunnath/kazoo"
    let session: URLSession
    let userAgent: String

    public init(session: URLSession = .shared, appVersion: String) {
        self.session = session
        self.userAgent = "Kazoo/\(appVersion) (macOS)"
    }

    public func latestRelease() async throws(UpdateCheckError) -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw .offline
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        switch http.statusCode {
        case 200: return try Self.parse(data)
        case 404: throw .noRelease
        case 403, 429: throw .rateLimited
        default: throw .invalidResponse
        }
    }

    static func parse(_ data: Data) throws(UpdateCheckError) -> ReleaseInfo {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let body: String?
            let published_at: Date?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name)
        else { throw .invalidResponse }
        let zip = payload.assets?.first { $0.name.hasPrefix("Kazoo-") && $0.name.hasSuffix(".zip") }
        let notes = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseInfo(
            version: version.description,
            tag: payload.tag_name,
            pageURL: payload.html_url,
            downloadURL: zip?.browser_download_url,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            publishedAt: payload.published_at)
    }
}
