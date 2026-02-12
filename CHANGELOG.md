# Changelog

## [3.0.0.3-SNAPSHOT] - 2026-02-11

### Fixed

- **Exception breakpoints now work in native mode (Lucee 7.1+)** - Fixed critical bug where onException() was never called for uncaught exceptions. Added onException() call in Lucee's PageContextImpl.java execute() catch block.
- Docker example .lco file deployment - Fixed COPY path in Dockerfile to correctly reference files from build context

### Changed

- Log prefix changed from `[luceedebug]` to `[debugger]` for consistency
- Exception logging now defaults to `true` (was `false`) - exception details are lost after continuing, so logging them makes sense
- Console output streaming now defaults to `true` (was `false`) - it's a debug tool, DX matters more than a bit of overhead
- onException() calls now log at DEBUG level instead of INFO - reduces noise in debug console

### Added

- Test infrastructure for exception logging configuration (logLevel and logExceptions parameters)
- Three new tests for exception logging behavior:
  - testExceptionLoggingWithLogExceptionsEnabled
  - testExceptionLoggingDisabled
  - testOnExceptionCalledLogsAtDebugLevel

### Removed

- Diagnostic logging from isDapClientConnected() - simplified to just return the boolean flag

## [3.0.0.2-SNAPSHOT] - 2026-01-30

### Changed

- Reduced client logging verbosity for cleaner debug output
- Improved Docker example documentation with detailed logging explanations

### Added

- Documentation for `LUCEE_DEBUGGER_DEBUG` environment variable for verbose server-side logging
- IDE integration tips for Neovim and JetBrains in Docker example README

## [3.0.0.1-SNAPSHOT] - 2026-01-28

### Added

- **Docker example** - Complete working example with Lucee 7.1 in Docker, includes VS Code, Neovim, and JetBrains configurations
- `LUCEE_DAP_HOST` environment variable for binding DAP server to specific addresses (default: localhost, use `0.0.0.0` for Docker)
- Maven Central publishing support in CI/CD
- AGENTS.md documentation for building from source

### Changed

- **Migrated from Gradle to Maven** build system
- VS Code extension migrated to lucee publisher for Marketplace release
- Updated tests to use published Lucee 7.1 alpha instead of custom builds

### Fixed

- .lex deployment with correct GAV (Group-Artifact-Version) in manifest
- CI deploy job GPG configuration
