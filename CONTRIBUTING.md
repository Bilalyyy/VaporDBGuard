# Contributing

Thanks for your interest in improving `VaporDBGuard`.

## Local setup

Requirements:

- Swift 6.2
- A working Swift Package Manager toolchain

Clone the repository and run:

```bash
swift test
```

## Project focus

`VaporDBGuard` is intentionally small and focused.

Please keep contributions aligned with the package goal:

- protect the first guarded DB-backed request after idle or resume
- stay safe for non-idempotent routes
- avoid replaying real business requests
- keep the integration simple for Vapor applications

## Pull requests

Before opening a PR, please make sure:

- tests pass locally with `swift test`
- documentation is updated when behavior or public usage changes
- new behavior is covered by tests when practical
- changes remain scoped and easy to review

## Good contribution ideas

- improve test coverage
- improve logging or observability
- improve docs and examples
- expand database support carefully and incrementally
- tighten edge-case behavior without making the middleware risky

## Reporting issues

When possible, include:

- your Swift, Vapor, and Fluent versions
- your deployment environment
- whether the app uses suspend, scale-to-zero, or aggressive idle connection handling
- relevant logs showing the probe behavior and the original DB error
