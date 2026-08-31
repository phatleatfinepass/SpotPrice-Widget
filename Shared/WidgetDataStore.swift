import Foundation

/// Per-process persistence for rebuildable API responses.
///
/// The free direct build is ad-hoc signed, so it deliberately avoids an App
/// Group entitlement. Each process keeps its own fallback cache. A reset clears
/// the host cache and asks WidgetKit to reload; a successful widget refresh then
/// replaces the extension's fallback cache with live data.
enum WidgetDataStore {
    static let spotPriceCacheKey = "finland-spot-price-cache-v1"
    static let gridForecastCacheKey = "finland-grid-forecast-cache-v1"
    static let gridEmissionsCacheKey = "finland-grid-emissions-cache-v2"

    private static let cacheKeys = [
        spotPriceCacheKey,
        gridForecastCacheKey,
        gridEmissionsCacheKey,
    ]

    static func defaults(preparing _: String) -> UserDefaults {
        .standard
    }

    /// Removes only rebuildable network caches from the calling process.
    static func resetCaches() {
        resetCaches(defaults: .standard)
        URLCache.shared.removeAllCachedResponses()
    }

    static func resetCaches(defaults: UserDefaults) {
        for cacheKey in cacheKeys {
            defaults.removeObject(forKey: cacheKey)
        }
    }
}
