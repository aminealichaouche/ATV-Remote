import Foundation

enum AppleTVIncludedApps {
    // Apple publishes case-sensitive bundle IDs for the preinstalled tvOS apps.
    // https://support.apple.com/guide/deployment/bundle-ids-for-apple-tv-apple-apps-depcdd66fe58/web
    static let bundleIDs: Set<String> = [
        "com.apple.TVAppStore",
        "com.apple.Arcade",
        "com.apple.facetime",
        "com.apple.Fitness",
        "com.apple.TVHomeSharing",
        "com.apple.TVMovies",
        "com.apple.TVMusic",
        "com.apple.TVPhotos",
        "com.apple.podcasts",
        "com.apple.TVSearch",
        "com.apple.TVSettings",
        "com.apple.Sing",
        "com.apple.TVWatchList",
        "com.apple.TVShows"
    ]

    static func contains(_ appID: String) -> Bool {
        bundleIDs.contains(appID)
    }
}

struct AppLibrarySections {
    let starred: [RemoteAppInfo]
    let downloaded: [RemoteAppInfo]
    let included: [RemoteAppInfo]

    init(apps: [RemoteAppInfo], starredIDs: Set<String>, search: String = "") {
        // Only the current TV's reported apps become rows. Stored stars for an
        // absent app remain preferences rather than phantom launch targets.
        var seenIDs = Set<String>()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let installed = apps.filter { seenIDs.insert($0.id).inserted }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.id.localizedCaseInsensitiveContains(query) }.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        starred = installed.filter { starredIDs.contains($0.id) }
        downloaded = installed.filter { !starredIDs.contains($0.id) && !AppleTVIncludedApps.contains($0.id) }
        included = installed.filter { !starredIDs.contains($0.id) && AppleTVIncludedApps.contains($0.id) }
    }
}
