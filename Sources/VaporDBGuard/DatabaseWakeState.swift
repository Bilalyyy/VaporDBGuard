//
//  DatabaseWakeState.swift
//  VaporDBGuard
//
//  Created by Bilal Larose on 19/03/2026.
//

import Foundation

actor DatabaseWakeState {
    private let suspiciousAfter: TimeInterval
    private var lastSuccessfulRequestAt: Date?
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
        if let lastSuccessfulRequestAt,
           now.timeIntervalSince(lastSuccessfulRequestAt) < suspiciousAfter {
            return .notNeeded(reason: "last successful DB access is still fresh")
        }

        if let currentProbe {
            return .joinExisting(task: currentProbe, reason: "joining in-flight DB wake probe")
        }

        let task = makeTask()
        currentProbe = task
        if let lastSuccessfulRequestAt {
            let idleFor = Int(now.timeIntervalSince(lastSuccessfulRequestAt))
            return .startNew(task: task, reason: "last successful DB access was \(idleFor)s ago")
        } else {
            return .startNew(task: task, reason: "no successful DB access recorded yet")
        }
    }

    func markDatabaseSuccess(at date: Date = Date()) {
        lastSuccessfulRequestAt = date
    }

    func finishProbe(at date: Date = Date()) {
        lastSuccessfulRequestAt = date
        currentProbe = nil
    }

    func failProbe() {
        currentProbe = nil
    }
}
