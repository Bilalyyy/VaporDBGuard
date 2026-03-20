//
//  DatabaseWakeMiddleware.swift
//  VaporDBGuard
//
//  Created by Bilal Larose on 19/03/2026.
//

import Vapor
import Fluent
import SQLKit
import PostgresNIO


struct DatabaseWakeMiddleware: AsyncMiddleware {
    private let state: DatabaseWakeState

    public init(suspiciousAfter: TimeInterval = 240) {
        self.state = DatabaseWakeState(suspiciousAfter: suspiciousAfter)
    }

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Never retry the user's real handler. We only warm up the DB path first.
        try await ensureDatabaseIsReady(for: req)

        let response = try await next.respond(to: req)
        await state.markDatabaseSuccess()

        req.logger.debug("[VaporDBGuard][DatabaseWakeMiddleware] recorded successful request access", metadata: logMetadata(for: req))
        return response
    }

    private func ensureDatabaseIsReady(for req: Request) async throws {
        let decision = await state.probeTaskIfNeeded(
            now: Date(),
            makeTask: {
                Task {
                    try await runProbe(on: req)
                }
            }
        )

        switch decision {
        case .notNeeded(let reason):
            req.logger.debug("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe skipped", metadata: logMetadata(for: req, extra: ["reason": .string(reason)]))
            return
        case .joinExisting(let probeTask, let reason):
            req.logger.info("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe waiting on existing task", metadata: logMetadata(for: req, extra: ["reason": .string(reason)]))
            try await awaitProbeTask(probeTask, state: state, req: req)
        case .startNew(let probeTask, let reason):
            req.logger.info("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe starting", metadata: logMetadata(for: req, extra: ["reason": .string(reason)]))
            try await awaitProbeTask(probeTask, state: state, req: req)
        }
    }

    private func awaitProbeTask(
        _ probeTask: Task<Void, any Error>,
        state: DatabaseWakeState,
        req: Request
    ) async throws {
        do {
            try await probeTask.value
            await state.finishProbe()
            req.logger.info("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe succeeded", metadata: logMetadata(for: req))
        } catch {
            await state.failProbe()
            req.logger.error("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe failed", metadata: logMetadata(for: req, extra: ["error": .string(String(reflecting: error))]))
            throw error
        }
    }

    private func runProbe(on req: Request) async throws {
        do {
            req.logger.debug("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe executing SQL health check", metadata: logMetadata(for: req))
            try await probeDatabase(on: req)
        } catch {
            guard isTransientDatabaseConnectionError(error) else {
                req.logger.error("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe hit a non-transient error", metadata: logMetadata(for: req, extra: ["error": .string(String(reflecting: error))]))
                throw error
            }

            req.logger.warning("[VaporDBGuard][DatabaseWakeMiddleware] Database wake probe hit a transient PostgreSQL connection error, retrying once", metadata: logMetadata(for: req, extra: ["error": .string(String(reflecting: error))]))
            // A single retry is enough to cover the wake-up case without turning
            // the probe itself into an unbounded recovery loop.
            try await probeDatabase(on: req)
        }
    }

    private func probeDatabase(on req: Request) async throws {
        guard let sql = req.db as? any SQLDatabase else {
            // If the configured database is not SQL-backed, the middleware has
            // nothing to probe and simply acts as a pass-through.
            return
        }

        try await sql.raw("SELECT 1").run()
    }

    private func isTransientDatabaseConnectionError(_ error: any Error) -> Bool {
        // We keep this intentionally narrow: only connection-level failures that
        // are known to happen around idle/suspend wake-up should trigger a retry.
        if let error = error as? any DatabaseError, error.isConnectionClosed {
            return true
        }

        if let error = error as? PSQLError {
            switch error.code {
            case .connectionError, .clientClosedConnection, .serverClosedConnection:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func logMetadata(for req: Request, extra: Logger.Metadata = [:]) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "path": .string(req.url.path),
            "method": .string(req.method.rawValue)
        ]

        if let requestID = req.headers.first(name: "x-request-id"), !requestID.isEmpty {
            metadata["request_id"] = .string(requestID)
        }

        for (key, value) in extra {
            metadata[key] = value
        }

        return metadata
    }
}
