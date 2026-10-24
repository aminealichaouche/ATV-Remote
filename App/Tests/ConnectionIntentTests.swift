import XCTest
@testable import RoomRemote

final class ConnectionIntentTests: XCTestCase {
    func testAutomaticActivationPreservesEstablishedAndPendingSessions() {
        let intent = ConnectionIntent()
        for state in [DeviceConnectionState.connected, .connecting, .awaitingApproval, .awaitingPin, .trustRequired(fingerprint: "fixture")] {
            XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple", state: state))
        }
    }

    func testAutomaticActivationRecoversLostSessionsButNotAnEmptySelection() {
        let intent = ConnectionIntent()
        for state in [DeviceConnectionState.disconnected, .failed("peer closed")] {
            XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-apple", state: state))
            XCTAssertFalse(intent.allowsAutomaticConnection(to: nil, state: state))
        }
    }

    func testBackgroundKeepsOnlyEstablishedConnections() {
        XCTAssertTrue(ConnectionLifecycle.preservesSessionOnBackground(.connected))
        for state in [DeviceConnectionState.disconnected, .failed("peer closed"), .connecting, .awaitingApproval, .awaitingPin, .trustRequired(fingerprint: "fixture")] {
            XCTAssertFalse(ConnectionLifecycle.preservesSessionOnBackground(state))
        }
    }

    func testLostConnectionCannotUndoManualDisconnectDuringActivation() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple", state: .failed("peer closed")))
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-samsung", state: .disconnected))
        intent.requestConnection(to: "living-room-apple")
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-apple", state: .disconnected))
    }

    func testNewSessionAutomaticallyConnectsSelectedTVsButNotAnEmptySlot() {
        let intent = ConnectionIntent()
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-apple"))
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-samsung"))
        XCTAssertFalse(intent.allowsAutomaticConnection(to: nil))
    }

    func testManualDisconnectBlocksRepeatedAutomaticRequestsForThatTV() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        // The same policy applies to a room re-selection and each foreground.
        for _ in 0..<3 { XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple")) }
    }

    func testManualDisconnectDoesNotHoldTheOtherTVOrAnotherRoom() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-samsung"))
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "family-room-apple"))
        XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple"))
    }

    func testSharedTVRetainsItsManualDisconnectAcrossRoomNames() {
        var intent = ConnectionIntent()
        let sharedTVID = "shared-apple"
        intent.disconnect(sharedTVID)
        let livingRoom = RoomProfile(name: "Living Room", appleID: sharedTVID)
        let familyRoom = RoomProfile(name: "Family Room", appleID: sharedTVID)
        XCTAssertFalse(intent.allowsAutomaticConnection(to: livingRoom.appleID))
        XCTAssertFalse(intent.allowsAutomaticConnection(to: familyRoom.appleID))
    }

    func testExplicitConnectReleasesOnlyTheRequestedTV() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        intent.disconnect("living-room-samsung")
        intent.requestConnection(to: "living-room-apple")
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-apple"))
        XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-samsung"))
    }

    func testRequestingADifferentTVCannotReleaseTheOriginalManualDisconnect() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        intent.requestConnection(to: "family-room-apple")
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "family-room-apple"))
        XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple"))
    }

    func testManualDisconnectAfterAnExplicitConnectRequiresAnotherExplicitRequest() {
        var intent = ConnectionIntent()
        intent.disconnect("living-room-apple")
        intent.requestConnection(to: "living-room-apple")
        intent.disconnect("living-room-apple")
        XCTAssertFalse(intent.allowsAutomaticConnection(to: "living-room-apple"))
        intent.requestConnection(to: "living-room-apple")
        XCTAssertTrue(intent.allowsAutomaticConnection(to: "living-room-apple"))
    }
}
