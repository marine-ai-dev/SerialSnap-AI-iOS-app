import Foundation

/// Where to find the SerialSnap Supabase project. Populated from
/// `SUPABASE_URL` / `SUPABASE_ANON_KEY`, which reach the app's Info.plist
/// via xcconfig build-setting substitution — see
/// `Config/Supabase.xcconfig.example` and `project.yml`. Never hardcode a
/// URL or key here: a missing developer config must fail loudly (see
/// `ConfigError`), never silently fall back to some baked-in dev project,
/// especially in a Release build.
public struct SupabaseConfig: Sendable {
    public let url: URL
    /// The **anonymous/public** API key only. Every request made with it is
    /// still subject to Postgres Row Level Security — see docs/SECURITY.md
    /// "Least privilege". The service-role key must never appear in this
    /// app's configuration.
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    public enum ConfigError: Error, CustomStringConvertible, Equatable {
        case missingURL
        case missingAnonKey
        case invalidURL(String)

        public var description: String {
            switch self {
            case .missingURL:
                return "SUPABASE_URL is missing from the app's Info.plist. Copy Config/Supabase.xcconfig.example to Config/Supabase.xcconfig, fill in your Supabase project's real URL and anon key, and rebuild. See docs/CLOUD_ARCHITECTURE.md."
            case .missingAnonKey:
                return "SUPABASE_ANON_KEY is missing from the app's Info.plist. Copy Config/Supabase.xcconfig.example to Config/Supabase.xcconfig, fill in your Supabase project's real URL and anon key, and rebuild. See docs/CLOUD_ARCHITECTURE.md."
            case .invalidURL(let raw):
                return "SUPABASE_URL ('\(raw)') in Config/Supabase.xcconfig is not a valid URL."
            }
        }
    }

    /// Reads the two required keys from a bundle's `infoDictionary`. Throws
    /// rather than falling back to a default, so a developer who forgot to
    /// create `Config/Supabase.xcconfig` gets a clear, actionable crash
    /// instead of the app silently talking to nothing (or, worse, to a
    /// stale hardcoded project) in Release.
    public static func fromInfoDictionary(_ infoDictionary: [String: Any]?) throws -> SupabaseConfig {
        guard let rawURL = infoDictionary?["SUPABASE_URL"] as? String, !rawURL.isEmpty else {
            throw ConfigError.missingURL
        }
        guard let anonKey = infoDictionary?["SUPABASE_ANON_KEY"] as? String, !anonKey.isEmpty else {
            throw ConfigError.missingAnonKey
        }
        guard let url = URL(string: rawURL) else {
            throw ConfigError.invalidURL(rawURL)
        }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}
