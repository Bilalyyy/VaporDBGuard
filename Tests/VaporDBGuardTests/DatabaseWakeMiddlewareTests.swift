import Testing
import Vapor
@testable import VaporDBGuard

@Test("Middleware probes on the first guarded request and skips the next fresh one")
func middlewareProbesThenSkipsWhileFresh() async throws {
    let runtime = ProbeRuntime()

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        _ = try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)
        _ = try await middleware.respond(to: makeRequest(app: app, path: "/api/v1/profile"), chainingTo: responder)

        #expect(await runtime.executedSQL == ["SELECT 1"])
        #expect(await responder.callCount == 2)
    }
}

@Test("Middleware retries the probe once on a transient connection error")
func middlewareRetriesOnceOnTransientConnectionError() async throws {
    let runtime = ProbeRuntime(outcomes: [.failure(.connectionClosed), .success])

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        _ = try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)

        #expect(await runtime.executedSQL == ["SELECT 1", "SELECT 1"])
        #expect(await responder.callCount == 1)
    }
}

@Test("Middleware does not retry non-transient probe failures")
func middlewareDoesNotRetryNonTransientProbeFailures() async throws {
    let runtime = ProbeRuntime(outcomes: [.failure(.nonTransient)])

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        await #expect(throws: ProbeFailure.nonTransient) {
            try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)
        }

        #expect(await runtime.executedSQL == ["SELECT 1"])
        #expect(await responder.callCount == 0)
    }
}

@Test("Middleware fails after the single retry is exhausted")
func middlewareFailsAfterSecondTransientProbeFailure() async throws {
    let runtime = ProbeRuntime(outcomes: [.failure(.connectionClosed), .failure(.connectionClosed)])

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        await #expect(throws: ProbeFailure.connectionClosed) {
            try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)
        }

        #expect(await runtime.executedSQL == ["SELECT 1", "SELECT 1"])
        #expect(await responder.callCount == 0)
    }
}

@Test("Middleware clears failed probe state so a later request can try again")
func middlewareCanRecoverAfterProbeFailure() async throws {
    let runtime = ProbeRuntime(outcomes: [.failure(.nonTransient), .success])

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        await #expect(throws: ProbeFailure.nonTransient) {
            try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)
        }

        _ = try await middleware.respond(to: makeRequest(app: app, path: "/admin/dashboard"), chainingTo: responder)

        #expect(await runtime.executedSQL == ["SELECT 1", "SELECT 1"])
        #expect(await responder.callCount == 1)
    }
}

@Test("Concurrent guarded requests share one in-flight probe")
func middlewareSharesProbeAcrossConcurrentRequests() async throws {
    let gate = AsyncGate()
    let runtime = ProbeRuntime(outcomes: [.blocked(gate)])

    try await withApp(.sql(runtime)) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        async let first: Response = middleware.respond(
            to: makeRequest(app: app, path: "/admin/dashboard"),
            chainingTo: responder
        )

        await runtime.waitUntilExecuted(count: 1)

        async let second: Response = middleware.respond(
            to: makeRequest(app: app, path: "/api/v1/auth/request-token"),
            chainingTo: responder
        )

        await Task.yield()
        await gate.open()

        _ = try await first
        _ = try await second

        #expect(await runtime.executedSQL == ["SELECT 1"])
        #expect(await responder.callCount == 2)
    }
}

@Test("Middleware acts as a pass-through when the configured DB is not SQL-capable")
func middlewarePassesThroughWithoutSQLDatabase() async throws {
    try await withApp(.nonSQL) { app in
        let middleware = DatabaseWakeMiddleware(suspiciousAfter: 240)
        let responder = TestResponder()

        _ = try await middleware.respond(to: makeRequest(app: app, path: "/health"), chainingTo: responder)
        _ = try await middleware.respond(to: makeRequest(app: app, path: "/health"), chainingTo: responder)

        #expect(await responder.callCount == 2)
    }
}

@Test("DBGuard.use registers the middleware on the application")
func dbGuardUseRegistersMiddleware() async throws {
    let app = try await Application.make(.testing)
    let initialCount = app.middleware.resolve().count

    app.dbGuard.use(suspiciousAfter: 42)

    #expect(app.middleware.resolve().count == initialCount + 1)
    try await app.asyncShutdown()
}
