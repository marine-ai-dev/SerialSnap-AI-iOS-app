import Foundation

/// Type-safe accessors for every user-facing string key in
/// `Localizable.xcstrings`. Views must go through `L10n`, never construct
/// `NSLocalizedString`/`String(localized:)` calls with inline literals —
/// this keeps every user-facing string enumerable and translatable from a
/// single source of truth.
public enum L10n {
    public enum Onboarding {
        public static var welcomeTitle: String { String(localized: "onboarding.welcome.title", bundle: .module) }
        public static var welcomeSubtitle: String { String(localized: "onboarding.welcome.subtitle", bundle: .module) }
    }

    public enum Auth {
        public static var signInWithApple: String { String(localized: "auth.signInWithApple", bundle: .module) }
    }

    public enum Workspace {
        public static var createTitle: String { String(localized: "workspace.create.title", bundle: .module) }
        public static var namePlaceholder: String { String(localized: "workspace.create.namePlaceholder", bundle: .module) }
        public static var selectTitle: String { String(localized: "workspace.select.title", bundle: .module) }
    }

    public enum Scanner {
        public static var title: String { String(localized: "scanner.title", bundle: .module) }
        public static var permissionDeniedTitle: String { String(localized: "scanner.permission.deniedTitle", bundle: .module) }
        public static var permissionDeniedMessage: String { String(localized: "scanner.permission.deniedMessage", bundle: .module) }
        public static var openSettings: String { String(localized: "scanner.permission.openSettings", bundle: .module) }
    }

    public enum Review {
        public static var title: String { String(localized: "review.title", bundle: .module) }
        public static var manufacturer: String { String(localized: "review.manufacturer", bundle: .module) }
        public static var model: String { String(localized: "review.model", bundle: .module) }
        public static var serialNumber: String { String(localized: "review.serialNumber", bundle: .module) }
        public static var assetTag: String { String(localized: "review.assetTag", bundle: .module) }
        public static var duplicateWarning: String { String(localized: "review.duplicateWarning", bundle: .module) }
        public static var ambiguousCharacterHint: String { String(localized: "review.ambiguousCharacterHint", bundle: .module) }
        public static var save: String { String(localized: "review.save", bundle: .module) }
    }

    public enum Confidence {
        public static var low: String { String(localized: "confidence.low", bundle: .module) }
        public static var medium: String { String(localized: "confidence.medium", bundle: .module) }
        public static var high: String { String(localized: "confidence.high", bundle: .module) }
    }

    public enum AssetsList {
        public static var title: String { String(localized: "assets.list.title", bundle: .module) }
        public static var searchPlaceholder: String { String(localized: "assets.list.searchPlaceholder", bundle: .module) }
        public static var empty: String { String(localized: "assets.list.empty", bundle: .module) }
        public static var syncPending: String { String(localized: "assets.list.syncPending", bundle: .module) }
        public static var syncFailed: String { String(localized: "assets.list.syncFailed", bundle: .module) }
    }

    public enum AssetDetail {
        public static var delete: String { String(localized: "assets.detail.delete", bundle: .module) }
        public static var deleteConfirm: String { String(localized: "assets.detail.deleteConfirm", bundle: .module) }
    }

    public enum Export {
        public static var title: String { String(localized: "export.title", bundle: .module) }
        public static var csv: String { String(localized: "export.csv", bundle: .module) }
        public static var json: String { String(localized: "export.json", bundle: .module) }
    }

    public enum Settings {
        public static var title: String { String(localized: "settings.title", bundle: .module) }
        public static var account: String { String(localized: "settings.account", bundle: .module) }
        public static var workspace: String { String(localized: "settings.workspace", bundle: .module) }
        public static var language: String { String(localized: "settings.language", bundle: .module) }
        public static var privacy: String { String(localized: "settings.privacy", bundle: .module) }
        public static var about: String { String(localized: "settings.about", bundle: .module) }
        public static var signOut: String { String(localized: "settings.signOut", bundle: .module) }
        public static var deleteAccount: String { String(localized: "settings.deleteAccount", bundle: .module) }
        public static var deleteAccountConfirm: String { String(localized: "settings.deleteAccountConfirm", bundle: .module) }
    }

    public enum Common {
        public static var cancel: String { String(localized: "common.cancel", bundle: .module) }
        public static var done: String { String(localized: "common.done", bundle: .module) }
        public static var retry: String { String(localized: "common.retry", bundle: .module) }
        public static var genericError: String { String(localized: "common.error.generic", bundle: .module) }
        public static var offlineError: String { String(localized: "common.error.offline", bundle: .module) }
    }
}
