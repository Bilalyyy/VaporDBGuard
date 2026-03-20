import Foundation
import Fluent
import NIOCore
import SQLKit
import Vapor

final class TaskFactoryTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _makeCount = 0

    var makeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _makeCount
    }

    func makeTask() -> Task<Void, any Error> {
        lock.lock()
        _makeCount += 1
        lock.unlock()

        return Task {
            try await Task.sleep(nanoseconds: 1)
        }
    }
}

enum ProbeFailure: Error, DatabaseError, Sendable {
    case connectionClosed
    case nonTransient

    var isSyntaxError: Bool { false }
    var isConstraintFailure: Bool { false }
    var isConnectionClosed: Bool { self == .connectionClosed }
}

actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor ProbeRuntime {
    enum Outcome: Sendable {
        case success
        case failure(ProbeFailure)
        case blocked(AsyncGate)
    }

    private var outcomes: [Outcome]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var executedSQL: [String] = []

    init(outcomes: [Outcome] = []) {
        self.outcomes = outcomes
    }

    func execute(sql: String) async throws {
        executedSQL.append(sql)
        resumeWaitersIfNeeded()

        let outcome = outcomes.isEmpty ? Outcome.success : outcomes.removeFirst()
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        case .blocked(let gate):
            await gate.wait()
        }
    }

    func waitUntilExecuted(count: Int) async {
        guard executedSQL.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private func resumeWaitersIfNeeded() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if executedSQL.count >= waiter.0 {
                waiter.1.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

struct TestResponder: AsyncResponder {
    private let state = ResponderState()

    var callCount: Int {
        get async { await state.callCount }
    }

    func respond(to request: Request) async throws -> Response {
        await state.recordCall()
        return Response(status: .ok)
    }
}

private actor ResponderState {
    private(set) var callCount = 0

    func recordCall() {
        callCount += 1
    }
}

enum DatabaseConfigurationKind {
    case sql(ProbeRuntime)
    case nonSQL
}

func withApp<R>(
    _ kind: DatabaseConfigurationKind,
    _ body: @Sendable (Application) async throws -> R
) async throws -> R {
    let app = try await makeApp(with: kind)
    do {
        let result = try await body(app)
        try await app.asyncShutdown()
        return result
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
}

private func makeApp(with kind: DatabaseConfigurationKind) async throws -> Application {
    let app = try await Application.make(.testing)

    switch kind {
    case .sql(let runtime):
        app.databases.use(
            TestDatabaseConfiguration { context in
                TestSQLDatabase(context: context, runtime: runtime)
            },
            as: DatabaseID(string: "test"),
            isDefault: true
        )
    case .nonSQL:
        app.databases.use(
            TestDatabaseConfiguration { context in
                TestPlainDatabase(context: context)
            },
            as: DatabaseID(string: "test"),
            isDefault: true
        )
    }

    return app
}

func makeRequest(
    app: Application,
    path: String,
    method: HTTPMethod = .GET,
    headers: HTTPHeaders = .init()
) -> Request {
    Request(
        application: app,
        method: method,
        url: URI(path: path),
        headersNoUpdate: headers,
        peerCertificateChain: nil,
        on: app.eventLoopGroup.any()
    )
}

private struct TestDatabaseConfiguration: DatabaseConfiguration {
    let makeDatabase: @Sendable (DatabaseContext) -> any Database
    var middleware: [any AnyModelMiddleware] = []

    func makeDriver(for databases: Databases) -> any DatabaseDriver {
        TestDatabaseDriver(makeDatabase: makeDatabase)
    }
}

private struct TestDatabaseDriver: DatabaseDriver {
    let makeDatabase: @Sendable (DatabaseContext) -> any Database

    func makeDatabase(with context: DatabaseContext) -> any Database {
        makeDatabase(context)
    }

    func shutdown() {}
}

private final class TestSQLDatabase: Database, SQLDatabase, @unchecked Sendable {
    let context: DatabaseContext
    let runtime: ProbeRuntime

    init(context: DatabaseContext, runtime: ProbeRuntime) {
        self.context = context
        self.runtime = runtime
    }

    var inTransaction: Bool { false }
    var dialect: any SQLDialect { TestDialect() }

    func execute(
        query: DatabaseQuery,
        onOutput: @escaping @Sendable (any DatabaseOutput) -> Void
    ) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func transaction<T>(
        _ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }

    func withConnection<T>(
        _ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }

    func execute(
        sql query: any SQLExpression,
        _ onRow: @escaping @Sendable (any SQLRow) -> Void
    ) -> EventLoopFuture<Void> {
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.completeWithTask {
            try await self.execute(sql: query, onRow)
        }
        return promise.futureResult
    }

    func execute(
        sql query: any SQLExpression,
        _ onRow: @escaping @Sendable (any SQLRow) -> Void
    ) async throws {
        try await runtime.execute(sql: serialize(query).sql)
    }
}

private final class TestPlainDatabase: Database, @unchecked Sendable {
    let context: DatabaseContext

    init(context: DatabaseContext) {
        self.context = context
    }

    var inTransaction: Bool { false }

    func execute(
        query: DatabaseQuery,
        onOutput: @escaping @Sendable (any DatabaseOutput) -> Void
    ) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> {
        context.eventLoop.makeSucceededFuture(())
    }

    func transaction<T>(
        _ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }

    func withConnection<T>(
        _ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        closure(self)
    }
}

private struct TestDialect: SQLDialect {
    var name: String { "test-dialect" }
    var identifierQuote: any SQLExpression { SQLRaw("\"") }
    var literalStringQuote: any SQLExpression { SQLRaw("'") }
    var supportsAutoIncrement: Bool { false }
    var autoIncrementClause: any SQLExpression { SQLRaw("") }

    func bindPlaceholder(at position: Int) -> any SQLExpression {
        SQLRaw("$\(position)")
    }

    func literalBoolean(_ value: Bool) -> any SQLExpression {
        SQLRaw(value ? "TRUE" : "FALSE")
    }
}