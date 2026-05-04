# Elixir
Write clear, concise and idiomatic Elixir code with a focus on clarity and maintainability.
Avoid building any unnecessary features or functionality.
Ask me if you want me to clarify any of my instructions or if you want me to choose from various architectures or designs.
Please don't write any Demo or example code for anything you create for me.
Tests will need to be run using the `just bash-run` command

## Testing
Focus on integration tests over plain unit tests unless there is some complex behaviour we want to ensure works as intended.
Use Mox to test with other systems.
No silent failures (So, e.g., don’t do this plan = Map.get(plan_map, frequency, "starter") — instead fail loudly with an ‘unknown frequency’ error.[10:40 AM]# Project guidelines
HTTP Requests: Use the already included and available `:req` (`Req`) library for HTTP requests
Behaviours for API Clients: Define behaviours for API clients to allow easy mocking
Error Handling: Handle network failures and unexpected responses gracefully
Timeouts: Always set appropriate timeouts for external calls
Circuit Breakers: Use circuit breakers for critical external services

## Phoenix Best Practices
LiveView-First: Use LiveView as the primary UI technology
Function Components: Use function components for reusable UI elements
PubSub for Real-time: Use Phoenix PubSub for real-time features
Thin Controllers: Keep controllers thin, delegating business logic to contexts
Security First: Always consider security implications (CSRF, XSS, etc.)

## General Elixir guidelines
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option
