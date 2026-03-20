//
//  DBGuard.swift
//  VaporDBGuard
//
//  Created by Bilal Larose on 19/03/2026.
//

import Vapor

public struct DBGuard {
    private let application: Application

    init(application: Application) {
        self.application = application
    }

    /// Registers the middleware once for the application's main middleware chain.
    ///
    /// `suspiciousAfter` is expressed in seconds and controls when the next
    /// request should proactively verify the database connection before letting
    /// the real handler run.
    public func use(suspiciousAfter: TimeInterval = 240) {
        application.middleware.use(
            DatabaseWakeMiddleware(suspiciousAfter: suspiciousAfter)
        )
    }
}

public extension Application {
    /// Convenience access point for configuring `VaporDBGuard`.
    var dbGuard: DBGuard {
        DBGuard(application: self)
    }
}
