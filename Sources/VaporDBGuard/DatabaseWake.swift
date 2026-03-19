//
//  DatabaseWake.swift
//  VaporDBGuard
//
//  Created by Bilal Larose on 19/03/2026.
//

import Vapor

extension Application {
    var databaseWake: DatabaseWake {
        .init(application: self)
    }

    struct DatabaseWake {
        let application: Application

        struct StateKey: StorageKey {
            typealias Value = DatabaseWakeState
        }

        var state: DatabaseWakeState {
            get {
                if let state = application.storage[StateKey.self] {
                    return state
                }

                let state = DatabaseWakeState(suspiciousAfter: 4 * 60)
                application.storage[StateKey.self] = state
                return state
            }
            nonmutating set {
                application.storage[StateKey.self] = newValue
            }
        }
    }
}
