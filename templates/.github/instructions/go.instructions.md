---
applyTo: "**/*.go"
---
Use table-driven tests with testify assertions as the default pattern.
Accept interfaces, return structs. Always pass context.Context as first parameter.
Wrap errors with context: `fmt.Errorf("operation: %w", err)`.
Package names: lowercase, short, no underscores (`user`, `auth`).
Exported: PascalCase. Unexported: camelCase.
