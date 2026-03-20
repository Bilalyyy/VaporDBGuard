# VaporDBGuard

Protect your Vapor app from stale Postgres connections after idle or resume.

`VaporDBGuard` is a lightweight middleware for Vapor + Fluent + Postgres. It
helps prevent the classic first-request failure that can happen after a machine
resumes or after a long idle period, when the process is still alive but some
database connections in the pool are no longer valid.

Typical symptom:

```
PSQLError: connection reset by peer
```

Instead of retrying the real HTTP request, `VaporDBGuard` runs a small database
probe first. If the probe hits a transient Postgres connection error, it
retries the probe once, then lets the real request continue.

## Why this package exists

This package was extracted from a real production fix.

When `auto_stop_machines = "suspend"`, the app process and Postgres
pool can survive in memory across suspend/resume cycles. In that state, the
first request touching PostgreSQL may reuse a dead TCP connection and fail.

`VaporDBGuard` is a focused mitigation for that exact problem:

- protects the first guarded request after a long idle period
- does not retry your business logic
- avoids aggressive full-pool reset in the request path
- keeps the latency benefits of `suspend`

## How it works

When a request goes through the middleware:

1. `VaporDBGuard` checks whether the app has been idle long enough to consider the DB state suspicious.
2. If needed, it runs `SELECT 1`.
3. If that probe fails with a transient Postgres connection error, it retries the probe once.
4. If the probe succeeds, the real request continues normally.

Important guarantees:

- the real HTTP request is never retried
- only the internal probe is retried
- concurrent requests can share the same in-flight probe

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/bilalyyy/VaporDBGuard.git", from: "1.0.0")
```

Then add the product to your target:

```swift
.product(name: "VaporDBGuard", package: "VaporDBGuard")
```

## Usage

Register the middleware in `configure.swift`:

```swift
import VaporDBGuard

app.dbGuard.use()
```

You can also customize the idle threshold:

```swift
app.dbGuard.use(suspiciousAfter: 240)
```

## Configuration

Public configuration currently available:

| Parameter | Default | Description |
| --- | --- | --- |
| `suspiciousAfter` | `240` | Number of seconds after which the DB is considered potentially stale |

## Best fit

`VaporDBGuard` is especially useful when your app runs in environments such as:

- Fly.io with `suspend`
- scale-to-zero platforms
- infrastructure where idle DB connections may be dropped underneath the app

It is particularly helpful for routes where replaying the full request would be
unsafe or undesirable, such as:

- auth endpoints
- session-backed pages
- admin routes
- other DB-backed routes with side effects

## Middleware order

Middleware order matters.

For best results, register `VaporDBGuard` so it protects your database-backed
application routes without unnecessarily wrapping static assets or unrelated
health endpoints.

In practice:

- let static file middleware run before it when possible
- keep it in front of the routes you want to protect
- tune `suspiciousAfter` if your app receives frequent non-DB traffic

## Scope

`VaporDBGuard` is intentionally focused.

Today it targets:

- Vapor
- Fluent
- Postgres

Its main goal is to protect the first guarded request after idle or resume. That
keeps the package small, predictable, and safe to adopt.

## Observability

The middleware emits logs for:

- probe start
- probe skip
- retry on transient error
- probe success
- probe failure

This makes it easy to validate behavior in production and confirm that the
middleware is absorbing wake-related connection issues.

## Notes

- The freshness decision is time-based.
- This package is a practical mitigation, not a deep pool repair mechanism.
- Support is currently focused on Postgres.

## Contributing

Contributions are welcome.

Issues, test improvements, and broader database support ideas are all useful.

## License

MIT © [Bilalyyy](https://github.com/Bilalyyy)
