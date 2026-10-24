import XCTest
@testable import RoomRemote

final class CommandRequestTests: XCTestCase {
    func testCancellationImmediatelyReleasesTheCommandSlot() throws {
        var commands = CommandRequests()
        let cancelled = try XCTUnwrap(commands.begin(for: .appleTV))
        commands.cancel(for: .appleTV)
        let replacement = try XCTUnwrap(commands.begin(for: .appleTV))
        XCTAssertFalse(commands.accepts(cancelled, for: .appleTV))
        XCTAssertTrue(commands.accepts(replacement, for: .appleTV))
    }

    func testOldCleanupCannotUnlockOrClearANewerCommand() throws {
        var commands = CommandRequests()
        let cancelled = try XCTUnwrap(commands.begin(for: .samsung))
        commands.cancel(for: .samsung)
        let replacement = try XCTUnwrap(commands.begin(for: .samsung))
        XCTAssertFalse(commands.finish(cancelled, for: .samsung))
        XCTAssertNil(commands.begin(for: .samsung))
        XCTAssertTrue(commands.accepts(replacement, for: .samsung))
        XCTAssertTrue(commands.finish(replacement, for: .samsung))
        XCTAssertNotNil(commands.begin(for: .samsung))
    }

    func testIndependentDriversDoNotBlockOrCancelEachOther() throws {
        var commands = CommandRequests()
        let navigation = try XCTUnwrap(commands.begin(for: .appleTV))
        let volume = try XCTUnwrap(commands.begin(for: .samsung))
        commands.cancel(for: .samsung)
        XCTAssertTrue(commands.accepts(navigation, for: .appleTV))
        XCTAssertFalse(commands.accepts(volume, for: .samsung))
        XCTAssertNil(commands.begin(for: .appleTV))
        XCTAssertNotNil(commands.begin(for: .samsung))
    }

    func testRejectedPreflightCleanupAllowsTheNextCommand() throws {
        var commands = CommandRequests()
        let request = try XCTUnwrap(commands.begin(for: .appleTV))
        // The Store installs this cleanup before its epoch/cancellation preflight guard.
        XCTAssertTrue(commands.finish(request, for: .appleTV))
        XCTAssertFalse(commands.finish(request, for: .appleTV))
        XCTAssertNotNil(commands.begin(for: .appleTV))
    }
}
