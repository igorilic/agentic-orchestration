---
applyTo: "**/*.cs"
---
Use xUnit for tests with FluentAssertions for assertions and NSubstitute for mocking.
Follow CQRS pattern with MediatR for command/query separation.
Use Result<T> pattern for expected failures — do not throw exceptions for business logic.
DTOs as C# records: `public record UserDto(int Id, string Name, string Email);`
Structure: Api → Application → Domain → Infrastructure.
Arrange-Act-Assert in all tests.
