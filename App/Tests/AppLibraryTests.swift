import XCTest
@testable import RoomRemote

final class AppLibraryTests: XCTestCase {
    func testStarredAppsMoveOutOfTheirOriginalSections() {
        let netflix = RemoteAppInfo(id: "com.netflix.Netflix", name: "Netflix")
        let music = RemoteAppInfo(id: "com.apple.TVMusic", name: "Music")
        let photos = RemoteAppInfo(id: "com.apple.TVPhotos", name: "Photos")
        let youtube = RemoteAppInfo(id: "com.google.ios.youtube", name: "YouTube")
        let sections = AppLibrarySections(apps: [youtube, netflix, photos, music], starredIDs: [netflix.id, music.id])

        XCTAssertEqual(sections.starred, [music, netflix])
        XCTAssertEqual(sections.downloaded, [youtube])
        XCTAssertEqual(sections.included, [photos])
        XCTAssertEqual(Set((sections.starred + sections.downloaded + sections.included).map(\.id)).count, 4)
    }

    func testImportedStarsOnlyShowInstalledAppsAndAppearWhenLaterInstalled() {
        let available = RemoteAppInfo(id: "com.example.available", name: "Available")
        let missing = RemoteAppInfo(id: "com.example.missing", name: "Missing")
        let imported: Set<String> = [available.id, missing.id]
        let beforeInstall = AppLibrarySections(apps: [available], starredIDs: imported)
        let afterInstall = AppLibrarySections(apps: [missing, available], starredIDs: imported)

        XCTAssertEqual(beforeInstall.starred, [available])
        XCTAssertTrue(beforeInstall.downloaded.isEmpty)
        XCTAssertTrue(beforeInstall.included.isEmpty)
        XCTAssertEqual(afterInstall.starred, [available, missing])
        XCTAssertEqual(imported, [available.id, missing.id])
    }

    func testEqualDisplayNamesDoNotShareStarOrClassification() {
        let downloaded = RemoteAppInfo(id: "com.example.music", name: "Music")
        let included = RemoteAppInfo(id: "com.apple.TVMusic", name: "Music")
        let sections = AppLibrarySections(apps: [downloaded, included], starredIDs: [downloaded.id])

        XCTAssertEqual(sections.starred, [downloaded])
        XCTAssertTrue(sections.downloaded.isEmpty)
        XCTAssertEqual(sections.included, [included])
    }

    func testIncludedAppsRequireExactDocumentedBundleID() {
        let documentedIDs = [
            "com.apple.TVAppStore", "com.apple.Arcade", "com.apple.facetime", "com.apple.Fitness",
            "com.apple.TVHomeSharing", "com.apple.TVMovies", "com.apple.TVMusic", "com.apple.TVPhotos",
            "com.apple.podcasts", "com.apple.TVSearch", "com.apple.TVSettings", "com.apple.Sing",
            "com.apple.TVWatchList", "com.apple.TVShows"
        ]
        for id in documentedIDs {
            XCTAssertTrue(AppleTVIncludedApps.contains(id), id)
        }
        for id in ["com.apple.TestFlight", "com.apple.Unknown", "com.apple.TVMusic.extra", "com.apple.tvmusic", "Music"] {
            XCTAssertFalse(AppleTVIncludedApps.contains(id), id)
        }
    }

    func testUnknownAppleAppsAndBuiltinDisplayNamesRemainDownloaded() {
        let testFlight = RemoteAppInfo(id: "com.apple.TestFlight", name: "TestFlight")
        let unknownApple = RemoteAppInfo(id: "com.apple.newApp", name: "New app")
        let misleadingName = RemoteAppInfo(id: "com.example.photos", name: "Photos")
        let actualIncluded = RemoteAppInfo(id: "com.apple.TVSettings", name: "Renamed Settings")
        let sections = AppLibrarySections(apps: [testFlight, actualIncluded, misleadingName, unknownApple], starredIDs: [])

        XCTAssertEqual(sections.downloaded, [unknownApple, misleadingName, testFlight])
        XCTAssertEqual(sections.included, [actualIncluded])
    }

    func testEachSectionSortsNamesIgnoringCaseWithBundleIDAsTieBreaker() {
        let starredA = RemoteAppInfo(id: "starred.a", name: "same")
        let starredZ = RemoteAppInfo(id: "starred.z", name: "SAME")
        let downloadedA = RemoteAppInfo(id: "downloaded.a", name: "Alpha")
        let downloadedZ = RemoteAppInfo(id: "downloaded.z", name: "zeta")
        let includedA = RemoteAppInfo(id: "com.apple.TVAppStore", name: "app store")
        let includedZ = RemoteAppInfo(id: "com.apple.TVWatchList", name: "TV")
        let sections = AppLibrarySections(
            apps: [starredZ, includedZ, downloadedZ, starredA, downloadedA, includedA],
            starredIDs: [starredA.id, starredZ.id]
        )

        XCTAssertEqual(sections.starred, [starredA, starredZ])
        XCTAssertEqual(sections.downloaded, [downloadedA, downloadedZ])
        XCTAssertEqual(sections.included, [includedA, includedZ])
    }

    func testDuplicateReportedBundleIDsNeverProduceDuplicateRows() {
        let first = RemoteAppInfo(id: "com.example.one", name: "First report")
        let duplicate = RemoteAppInfo(id: first.id, name: "Duplicate report")
        let included = RemoteAppInfo(id: "com.apple.TVPhotos", name: "Photos")
        let sections = AppLibrarySections(apps: [first, included, duplicate, included], starredIDs: [first.id])

        XCTAssertEqual(sections.starred, [first])
        XCTAssertTrue(sections.downloaded.isEmpty)
        XCTAssertEqual(sections.included, [included])
    }

    func testNoInstalledAppsProducesNoRowsDespiteStoredStars() {
        let sections = AppLibrarySections(apps: [], starredIDs: ["com.apple.TVMusic", "com.example.notInstalled"])

        XCTAssertTrue(sections.starred.isEmpty)
        XCTAssertTrue(sections.downloaded.isEmpty)
        XCTAssertTrue(sections.included.isEmpty)
    }
}
