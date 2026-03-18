---
applyTo: "**/*.rs"
---
Use thiserror for library error types, anyhow for application error handling.
Prefer axum for web services with tokio async runtime.
Derive liberally: `#[derive(Debug, Clone, Serialize, Deserialize)]`.
Tests in `#[cfg(test)] mod tests` within the same file.
Use `#[tokio::test]` for async tests.
