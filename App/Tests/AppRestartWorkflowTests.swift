import Foundation
import XCTest
@testable import RoomRemote

final class AppRestartWorkflowTests: XCTestCase {
    private func context(deviceID: String = "apple-living-room", sessionID: UUID = UUID(),
                         appID: String = AppRestartWorkflow.xfinityAppID) -> AppleAppRestartContext {
        AppleAppRestartContext(deviceID: deviceID, sessionID: sessionID, appID: appID)
    }

    private func assertFailure(_ operation: () async throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected the shortcut to stop", file: file, line: line) }
        catch { }
    }

    private func assertCancellation(_ task: Task<Void, Error>,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        do { try await task.value; XCTFail("Expected cancellation", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line) }
    }

    func testPrepareFetchesFreshExactAppThenShowsSwitcherInOrder() async throws {
        let context = context()
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context)
        try await workflow.prepare()
        let events = await fixture.events
        XCTAssertEqual(events, [.apps, .launch(AppRestartWorkflow.xfinityAppID), .wait(2_000_000_000),
                                .switcher, .wait(1_000_000_000)])
    }

    func testOnePassMacroClosesOnceAndRelaunchesWithoutCardConfirmation() async throws {
        let context = context()
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context)
        try await workflow.run()
        let events = await fixture.events
        XCTAssertEqual(events.filter { $0 == .launch(context.appID) }.count, 2)
        XCTAssertEqual(events.filter { $0 == .switcher }.count, 1)
        XCTAssertEqual(events.filter { if case .touch(let point) = $0 { return point.phase == .press }; return false }.count, 1)
        XCTAssertEqual(events.last, .launch(context.appID))
    }

    func testExplicitInstalledAppTargetUsesSameMacroWithoutSubstitutingXfinity() async throws {
        let context = context(appID: "com.example.Player")
        let fixture = RestartFixture(context: context, appIDs: [context.appID, AppRestartWorkflow.xfinityAppID])
        let workflow = await fixture.workflow(context: context)
        try await workflow.run()
        let events = await fixture.events
        XCTAssertEqual(events.filter { $0 == .launch(context.appID) }.count, 2)
        XCTAssertFalse(events.contains(.launch(AppRestartWorkflow.xfinityAppID)))
    }

    func testMissingTargetStopsBeforeLaunchSwitcherOrTouch() async {
        let context = context(appID: "com.example.Player")
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context)
        await assertFailure { try await workflow.run() }
        let events = await fixture.events
        XCTAssertEqual(events, [.apps])
    }

    func testPreparationObserverFailureStopsBeforeDestructiveGesture() async {
        let context = context()
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context)
        await assertFailure { try await workflow.run { throw CancellationError() } }
        let events = await fixture.events
        XCTAssertEqual(events.filter { $0 == .launch(context.appID) }.count, 1)
        XCTAssertFalse(events.contains { if case .touch = $0 { return true }; return false })
    }

    func testUnavailableSwipeRejectsBeforeFetchingOrLaunchingAnyApp() async {
        let context = context()
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context, supportsSwipe: false)
        await assertFailure { try await workflow.prepare() }
        await assertFailure { try await workflow.finish() }
        let events = await fixture.events
        XCTAssertTrue(events.isEmpty)
    }

    func testMissingExactBundleIDDoesNotLaunchANameOrSimilarIdentifier() async {
        let context = context()
        let fixture = RestartFixture(context: context,
            appIDs: ["Xfinity", "com.comcast.cim.x2.other", "COM.COMCAST.CIM.X2"])
        let workflow = await fixture.workflow(context: context)
        await assertFailure { try await workflow.prepare() }
        let events = await fixture.events
        XCTAssertEqual(events, [.apps])
    }

    func testFinishSendsOneFastFullHeightGestureThenDirectExactRelaunch() async throws {
        let context = context()
        let fixture = RestartFixture(context: context)
        let workflow = await fixture.workflow(context: context)
        try await workflow.finish()
        let events = await fixture.events
        let touches = events.compactMap { event -> AppRestartWorkflow.TouchSample? in
            if case .touch(let point) = event { return point }; return nil
        }
        XCTAssertEqual(touches.count, 8)
        XCTAssertEqual(touches.first, .init(x: 500, y: 1000, phase: .press))
        XCTAssertEqual(touches.last, .init(x: 500, y: 0, phase: .release))
        XCTAssertEqual(touches.filter { $0.phase == .press }.count, 1)
        XCTAssertEqual(touches.filter { $0.phase == .hold }.count, 6)
        XCTAssertEqual(touches.filter { $0.phase == .release }.count, 1)
        XCTAssertTrue(touches.allSatisfy { $0.x == 500 && (0...1000).contains($0.y) })
        let movement = Array(touches.dropLast())
        for pair in zip(movement, movement.dropFirst()) {
            XCTAssertTrue((166...167).contains(pair.0.y - pair.1.y), "The flick must keep moving upward")
        }
        XCTAssertEqual(movement.last, .init(x: 500, y: 0, phase: .hold))
        XCTAssertEqual(events.first, .touch(.init(x: 500, y: 1000, phase: .press)))
        // Every move follows a cancellable 16 ms wait, including the first
        // after press and the release after the endpoint hold: 112 ms of planned waits; I/O adds actual elapsed time.
        for index in 0..<7 {
            XCTAssertEqual(events[1 + index * 2], .wait(16_000_000))
            guard case .touch = events[2 + index * 2] else { return XCTFail("Missing paced touch") }
        }
        XCTAssertEqual(events.filter { $0 == .wait(16_000_000) }.count, 7)
        XCTAssertEqual(Array(events.suffix(2)), [.wait(1_200_000_000), .launch(AppRestartWorkflow.xfinityAppID)])
        XCTAssertFalse(events.contains(.back))
        XCTAssertFalse(events.contains { if case .cleanup = $0 { return true }; return false })
    }

    func testCancellationDuringPrepareWaitStopsBeforeSwitcherWithoutRetry() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, blockWait: 2_000_000_000)
        let workflow = await fixture.workflow(context: context)
        let task = Task { try await workflow.prepare() }
        try await fixture.waitUntilBlocked()
        task.cancel()
        await fixture.unblock()
        await assertCancellation(task)
        let events = await fixture.events
        XCTAssertEqual(events, [.apps, .launch(AppRestartWorkflow.xfinityAppID), .wait(2_000_000_000)])
    }

    func testCancellationDuringSwipeStopsRemainingFramesAndReleasesOriginalTouch() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, blockWait: 16_000_000)
        let workflow = await fixture.workflow(context: context)
        let task = Task { try await workflow.finish() }
        try await fixture.waitUntilBlocked()
        task.cancel()
        await fixture.unblock()
        await assertCancellation(task)
        let events = await fixture.events
        XCTAssertEqual(events, [.touch(.init(x: 500, y: 1000, phase: .press)), .wait(16_000_000),
                                .cleanup(.init(x: 500, y: 1000, phase: .release))])
    }

    func testCancellationAfterTerminalHoldReleasesOriginalEndpointWithoutBackOrRelaunch() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, blockWait: 16_000_000, blockWaitOccurrence: 7)
        let workflow = await fixture.workflow(context: context)
        let task = Task { try await workflow.finish() }
        try await fixture.waitUntilBlocked()
        task.cancel()
        await fixture.unblock()
        await assertCancellation(task)
        let events = await fixture.events
        XCTAssertEqual(Array(events.suffix(3)), [.touch(.init(x: 500, y: 0, phase: .hold)),
                                               .wait(16_000_000),
                                               .cleanup(.init(x: 500, y: 0, phase: .release))])
        XCTAssertEqual(events.filter { if case .touch(let point) = $0 { return point.phase == .press }; return false }.count, 1)
        XCTAssertFalse(events.contains { if case .touch(let point) = $0 { return point.phase == .release }; return false })
        XCTAssertFalse(events.contains(.back))
        XCTAssertFalse(events.contains(.launch(context.appID)))
    }

    func testPassiveContextInvalidationMidSwipeStopsWithoutTaskCancellationOrNewTargetEffects() async throws {
        let context = context()
        let original = RestartFixture(context: context, blockWait: 16_000_000)
        let replacementContext = self.context(deviceID: "apple-bedroom")
        let replacement = RestartFixture(context: replacementContext)
        let workflow = await original.workflow(context: context)
        let task = Task { try await workflow.finish() }
        try await original.waitUntilBlocked()
        // Models passive cancel/session replacement without relying on Task.cancel.
        await original.invalidate(to: replacementContext)
        await original.unblock()
        await assertCancellation(task)
        let originalEvents = await original.events
        let replacementEvents = await replacement.events
        XCTAssertEqual(originalEvents, [.touch(.init(x: 500, y: 1000, phase: .press)), .wait(16_000_000),
                                        .cleanup(.init(x: 500, y: 1000, phase: .release))])
        XCTAssertTrue(replacementEvents.isEmpty)
    }

    func testStaleDeviceSessionAndPreparationContextsRejectAllEffects() async {
        let current = context()
        let staleContexts = [
            context(deviceID: "apple-bedroom", sessionID: current.sessionID),
            context(deviceID: current.deviceID),
            context(deviceID: current.deviceID, sessionID: current.sessionID)
        ]
        for stale in staleContexts {
            let fixture = RestartFixture(context: current)
            let workflow = await fixture.workflow(context: stale)
            await assertFailure { try await workflow.prepare() }
            await assertFailure { try await workflow.finish() }
            let events = await fixture.events
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testMalformedTargetContextRejectsBeforeAnyEffect() async {
        for context in [context(deviceID: ""), context(appID: "https://example.com")] {
            let fixture = RestartFixture(context: context)
            let workflow = await fixture.workflow(context: context)
            await assertFailure { try await workflow.prepare() }
            await assertFailure { try await workflow.finish() }
            let events = await fixture.events
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testPrepareFailuresStopTheSequenceWithoutAutomaticRetry() async {
        let context = context()
        for failure in [RestartFixture.Effect.launch(context.appID), .switcher] {
            let fixture = RestartFixture(context: context, failAt: failure)
            let workflow = await fixture.workflow(context: context)
            await assertFailure { try await workflow.prepare() }
            let events = await fixture.events
            XCTAssertEqual(events.last, failure)
            XCTAssertEqual(events.filter { $0 == failure }.count, 1)
            XCTAssertFalse(events.contains(.wait(1_000_000_000)))
        }
    }

    func testFailedTouchReleasesOriginalPointAndNeverBacksOrRelaunches() async {
        let context = context()
        let failedPoint = AppRestartWorkflow.TouchSample(x: 500, y: 500, phase: .hold)
        let fixture = RestartFixture(context: context, failAt: .touch(failedPoint))
        let workflow = await fixture.workflow(context: context)
        await assertFailure { try await workflow.finish() }
        let events = await fixture.events
        XCTAssertEqual(events.last, .cleanup(.init(x: 500, y: 500, phase: .release)))
        XCTAssertEqual(events.filter { $0 == .touch(failedPoint) }.count, 1)
        XCTAssertFalse(events.contains(.back))
        XCTAssertFalse(events.contains(.launch(context.appID)))
    }

    func testFailedReleaseCleansUpOriginalEndpointWithoutRepeatingGestureOrRelaunching() async {
        let context = context()
        let failedRelease = AppRestartWorkflow.TouchSample(x: 500, y: 0, phase: .release)
        let fixture = RestartFixture(context: context, failAt: .touch(failedRelease))
        let workflow = await fixture.workflow(context: context)
        await assertFailure { try await workflow.finish() }
        let events = await fixture.events
        XCTAssertEqual(Array(events.suffix(4)), [.touch(.init(x: 500, y: 0, phase: .hold)),
                                               .wait(16_000_000), .touch(failedRelease),
                                               .cleanup(failedRelease)])
        XCTAssertEqual(events.filter { $0 == .touch(failedRelease) }.count, 1)
        XCTAssertEqual(events.filter { $0 == .cleanup(failedRelease) }.count, 1)
        XCTAssertEqual(events.filter { if case .touch(let point) = $0 { return point.phase == .press }; return false }.count, 1)
        XCTAssertFalse(events.contains(.back))
        XCTAssertFalse(events.contains(.launch(context.appID)))
    }

    func testFailedFinalLaunchReportsReopenStageWithoutRepeatingCloseOrLaunch() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, failAt: .launch(context.appID), failAtOccurrence: 2)
        let workflow = await fixture.workflow(context: context)
        do {
            try await workflow.run()
            XCTFail("Expected final launch to fail")
        } catch let error as AppRestartFailure {
            XCTAssertEqual(error.stage, .reopening)
            XCTAssertTrue(error.underlying is RestartFixture.Failure)
        }
        let events = await fixture.events
        XCTAssertEqual(events.last, .launch(context.appID))
        XCTAssertEqual(events.filter { $0 == .launch(context.appID) }.count, 2)
        XCTAssertEqual(events.filter { if case .touch(let point) = $0 { return point.phase == .press }; return false }.count, 1)
        XCTAssertFalse(events.contains(.back))
    }

    func testCancellationAfterCloseDoesNotRelaunchOrSendAnotherGesture() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, blockWait: 1_200_000_000)
        let workflow = await fixture.workflow(context: context)
        let task = Task { try await workflow.finish() }
        try await fixture.waitUntilBlocked()
        task.cancel()
        await fixture.unblock()
        await assertCancellation(task)
        let events = await fixture.events
        XCTAssertFalse(events.contains(.launch(context.appID)))
        XCTAssertFalse(events.contains(.back))
        XCTAssertEqual(events.filter { if case .touch(let point) = $0 { return point.phase == .press }; return false }.count, 1)
        XCTAssertFalse(events.contains { if case .cleanup = $0 { return true }; return false })
    }

    func testSessionChangesDuringCloseAnimationPreventRelaunchToAnyTV() async throws {
        let context = context()
        let fixture = RestartFixture(context: context, blockWait: 1_200_000_000)
        let workflow = await fixture.workflow(context: context)
        let task = Task { try await workflow.finish() }
        try await fixture.waitUntilBlocked()
        await fixture.invalidate(to: self.context())
        await fixture.unblock()
        await assertCancellation(task)
        let events = await fixture.events
        XCTAssertFalse(events.contains(.launch(context.appID)))
        XCTAssertFalse(events.contains(.back))
    }

    func testCancelledTaskSendsNothing() async throws {
        let context = context()
        let cancelledFixture = RestartFixture(context: context)
        let cancelledWorkflow = await cancelledFixture.workflow(context: context)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await cancelledWorkflow.finish()
        }
        await assertCancellation(task)
        let cancelledEvents = await cancelledFixture.events
        XCTAssertTrue(cancelledEvents.isEmpty)
    }
}

/// The production runner uses these same effect closures. Only protocol I/O and
/// waits are substituted; no TV, Keychain, clock delay or mock app list reaches
/// the shipped driver. Blocking waits make suspension/cancellation observable.
private actor RestartFixture {
    enum Effect: Equatable, Sendable {
        case apps, launch(String), switcher, back, move(RemoteAction), wait(UInt64)
        case touch(AppRestartWorkflow.TouchSample), cleanup(AppRestartWorkflow.TouchSample)
    }
    struct Failure: Error { }

    var events: [Effect] = []
    private var activeContext: AppleAppRestartContext
    private let appIDs: [String]
    private let failAt: Effect?
    private let failAtOccurrence: Int
    private var matchingFailures = 0
    private let blockWait: UInt64?
    private let blockWaitOccurrence: Int
    private var matchingWaits = 0
    private var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(context: AppleAppRestartContext, appIDs: [String] = [AppRestartWorkflow.xfinityAppID],
         failAt: Effect? = nil, failAtOccurrence: Int = 1, blockWait: UInt64? = nil, blockWaitOccurrence: Int = 1) {
        activeContext = context
        self.appIDs = appIDs
        self.failAt = failAt
        self.failAtOccurrence = failAtOccurrence
        self.blockWait = blockWait
        self.blockWaitOccurrence = blockWaitOccurrence
    }

    func workflow(context: AppleAppRestartContext, supportsSwipe: Bool = true) -> AppRestartWorkflow {
        AppRestartWorkflow(context: context, supportsSwipe: supportsSwipe, steps: .init(
            validate: { try await self.validate($0) },
            fetchAppIDs: { try await self.fetchApps() },
            launchApp: { try await self.record(.launch($0)) },
            showSwitcher: { try await self.record(.switcher) },
            wait: { try await self.wait($0) },
            touch: { try await self.record(.touch($0)) },
            releaseOriginalTouch: { await self.cleanup($0) }
        ))
    }

    func invalidate(to context: AppleAppRestartContext) { activeContext = context }

    func waitUntilBlocked() async throws {
        for _ in 0..<2_000 {
            if blocked { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw Failure()
    }

    func unblock() { continuation?.resume(); continuation = nil }

    private func validate(_ context: AppleAppRestartContext) throws {
        guard context == activeContext else { throw CancellationError() }
    }

    private func record(_ effect: Effect) throws {
        events.append(effect)
        if effect == failAt {
            matchingFailures += 1
            if matchingFailures == failAtOccurrence { throw Failure() }
        }
    }

    private func fetchApps() throws -> [String] { try record(.apps); return appIDs }

    private func wait(_ duration: UInt64) async throws {
        try record(.wait(duration))
        if duration == blockWait {
            matchingWaits += 1
            if matchingWaits == blockWaitOccurrence && !blocked {
                blocked = true
                await withCheckedContinuation { continuation = $0 }
            }
        }
        try Task.checkCancellation()
    }

    private func cleanup(_ point: AppRestartWorkflow.TouchSample) {
        events.append(.cleanup(point))
    }
}
