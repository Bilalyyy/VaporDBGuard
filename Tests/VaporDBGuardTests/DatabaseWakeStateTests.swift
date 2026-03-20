import Foundation
import Testing
@testable import VaporDBGuard

@Test("State starts a new probe when no success has been recorded")
func stateStartsNewProbeWithoutPreviousSuccess() async {
    let state = DatabaseWakeState(suspiciousAfter: 240)
    let tracker = TaskFactoryTracker()

    let decision = await state.probeTaskIfNeeded(
        now: .init(timeIntervalSince1970: 1_000),
        makeTask: tracker.makeTask
    )

    guard case .startNew = decision else {
        Issue.record("Expected a new probe to start")
        return
    }

    #expect(tracker.makeCount == 1)
}

@Test("State skips the probe while still fresh")
func stateSkipsProbeWhenFresh() async {
    let state = DatabaseWakeState(suspiciousAfter: 240)
    let tracker = TaskFactoryTracker()
    let start = Date(timeIntervalSince1970: 1_000)

    await state.markDatabaseSuccess(at: start)

    let decision = await state.probeTaskIfNeeded(
        now: start.addingTimeInterval(120),
        makeTask: tracker.makeTask
    )

    guard case .notNeeded = decision else {
        Issue.record("Expected the probe to be skipped")
        return
    }

    #expect(tracker.makeCount == 0)
}

@Test("State starts a new probe again at the suspiciousAfter boundary")
func stateStartsNewProbeAtThresholdBoundary() async {
    let state = DatabaseWakeState(suspiciousAfter: 240)
    let tracker = TaskFactoryTracker()
    let start = Date(timeIntervalSince1970: 1_000)

    await state.markDatabaseSuccess(at: start)

    let decision = await state.probeTaskIfNeeded(
        now: start.addingTimeInterval(240),
        makeTask: tracker.makeTask
    )

    guard case .startNew = decision else {
        Issue.record("Expected a new probe once the freshness threshold is reached")
        return
    }

    #expect(tracker.makeCount == 1)
}

@Test("State joins the running probe and becomes fresh after completion")
func stateJoinsExistingProbeAndBecomesFreshAfterCompletion() async {
    let state = DatabaseWakeState(suspiciousAfter: 240)
    let tracker = TaskFactoryTracker()
    let clock = Date(timeIntervalSince1970: 1_000)

    let firstDecision = await state.probeTaskIfNeeded(now: clock, makeTask: tracker.makeTask)
    guard case .startNew = firstDecision else {
        Issue.record("Expected the first probe decision to start a task")
        return
    }

    let secondDecision = await state.probeTaskIfNeeded(
        now: clock.addingTimeInterval(1),
        makeTask: tracker.makeTask
    )

    guard case .joinExisting = secondDecision else {
        Issue.record("Expected to join the running probe")
        return
    }

    await state.finishProbe(at: clock.addingTimeInterval(2))

    let thirdDecision = await state.probeTaskIfNeeded(
        now: clock.addingTimeInterval(3),
        makeTask: tracker.makeTask
    )

    guard case .notNeeded = thirdDecision else {
        Issue.record("Expected freshness right after a successful probe")
        return
    }

    #expect(tracker.makeCount == 1)
}

@Test("State clears failed probes so the next request can retry")
func stateAllowsRetryAfterProbeFailure() async {
    let state = DatabaseWakeState(suspiciousAfter: 240)
    let tracker = TaskFactoryTracker()
    let clock = Date(timeIntervalSince1970: 1_000)

    _ = await state.probeTaskIfNeeded(now: clock, makeTask: tracker.makeTask)
    await state.failProbe()

    let decision = await state.probeTaskIfNeeded(
        now: clock.addingTimeInterval(1),
        makeTask: tracker.makeTask
    )

    guard case .startNew = decision else {
        Issue.record("Expected a new probe after the previous one failed")
        return
    }

    #expect(tracker.makeCount == 2)
}
