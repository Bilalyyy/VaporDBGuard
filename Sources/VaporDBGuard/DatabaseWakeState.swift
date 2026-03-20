//
//  DatabaseWakeState.swift
//  VaporDBGuard
//
//  Created by Bilal Larose on 19/03/2026.
//

import Foundation

actor DatabaseWakeState {
    private let suspiciousAfter: TimeInterval
    // This is intentionally request-level state, not a strict "last DB query"
    // timestamp. The middleware uses it as a lightweight freshness heuristic.
    private var lastSuccessfulRequestAt: Date?
    // When several requests arrive together after a long idle period, they
    // should wait on the same probe instead of each starting their own.
    private var currentProbe: Task<Void, any Error>?

    init(suspiciousAfter: TimeInterval) {
        self.suspiciousAfter = suspiciousAfter
    }

    enum ProbeDecision {
        case notNeeded(reason: String)
        case joinExisting(task: Task<Void, any Error>, reason: String)
        case startNew(task: Task<Void, any Error>, reason: String)
    }

    func probeTaskIfNeeded(
        now: Date,
        makeTask: @escaping @Sendable () -> Task<Void, any Error>
    ) -> ProbeDecision {
        // Fresh requests can pass through without paying the probe cost again.
        if let lastSuccessfulRequestAt,
           now.timeIntervalSince(lastSuccessfulRequestAt) < suspiciousAfter {
            return .notNeeded(reason: "last successful request access is still fresh")
        }

        if let currentProbe {
            return .joinExisting(task: currentProbe, reason: "joining in-flight DB wake probe")
        }

        let task = makeTask()
        currentProbe = task
        if let lastSuccessfulRequestAt {
            let idleFor = Int(now.timeIntervalSince(lastSuccessfulRequestAt))
            return .startNew(task: task, reason: "last successful request access was \(idleFor)s ago")
        } else {
            return .startNew(task: task, reason: "no successful request access recorded yet")
        }
    }

    func markDatabaseSuccess(at date: Date = Date()) {
        lastSuccessfulRequestAt = date
    }

    func finishProbe(at date: Date = Date()) {
        // A successful probe refreshes the heuristic and releases any followers.
        lastSuccessfulRequestAt = date
        currentProbe = nil
    }

    func failProbe() {
        // Clearing the in-flight task lets the next request attempt a fresh probe.
        currentProbe = nil
    }
}
