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

    public func use(suspiciousAfter: TimeInterval = 240) {
        application.middleware.use(
            DatabaseWakeMiddleware(suspiciousAfter: suspiciousAfter)
        )
    }
}

public extension Application {
    var dbGuard: DBGuard {
        DBGuard(application: self)
    }
}
