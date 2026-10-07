---
name: verify
description: Run the project's real check and report the exact result. Use before every commit and before saying a task is done.
---
Run `./.anw/verify` if it exists. Otherwise run the project's test command (Makefile `test`, `npm test`, `dotnet test`, `go test ./...`, `cargo test`, `pytest -q`, `swift test`).

Quote the exact pass/fail summary, or the first failure. A syntax-only check, or a command that failed to start, is not verification. If nothing can run, say so plainly.
