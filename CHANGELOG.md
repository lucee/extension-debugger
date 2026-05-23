# Changelog

## [3.0.0.8-SNAPSHOT] - 2026-05-22

### Fixed

- **[LDEV-6339](https://luceeserver.atlassian.net/browse/LDEV-6339)**: native-mode debugger polish (all sub-items are native-only unless noted):
  - Variables panel no longer ClassCastExceptions when expanding a Component — only agent-mode `ComponentImpl` has `ComponentScopeMarkerTraitShim` mixed in via bytecode; the native cast is now gated by `instanceof`
  - Variables panel honours VSCode's `start`/`count` pagination request and reports `indexedVariables`/`namedVariables` so large arrays and structs are chunked instead of streamed in one shot (both modes)
  - Debug console accepts expressions without a selected frame — evaluates against any suspended `PageContext` instead of returning "missing frameID" (native only; agent's no-frame eval returns the "not paused" default)
  - Expanding a Component now splits into `this` / `variables` / `static` / `functions` / `accessors` sub-groups (empty groups omitted); the `functions` and `accessors` groups render full signatures derived from `getMetaData(cfc)` (auto-generated accessors derived from the property declaration). Agent mode expands to a flat list with noisy UDFs filtered.
  - Variables panel exposes additional scopes: `cookie`, `cfthread`, `applicationContext`, `systemMetrics`
- **[LDEV-6337](https://luceeserver.atlassian.net/browse/LDEV-6337)** (native only — Lucee 7.1+): Variables panel now shows the right `variables` scope on top-level CFM pages (was missing entirely) and inside custom-tag bodies (was leaking the caller's scope). Core fix on the INCLUDE debugger frame; existing specs for top-level CFM, cfmodule, and top-level exception-suspend now pass once the minimum core picks up the fix.

### Changed

- Minimum Lucee core version raised to **7.1.0.134**

## [3.0.0.7-SNAPSHOT] - 2026-05-21

### Fixed

- **[LDEV-6335](https://luceeserver.atlassian.net/browse/LDEV-6335)**: native step-over now advances by source line rather than by ExecutionLog instrumentation block — multi-expression lines (e.g. `<cfset c = a & b>`) no longer require two clicks to advance past
- **[LDEV-6334](https://luceeserver.atlassian.net/browse/LDEV-6334)**: stale frame IDs after step/continue resolve to the owning request's live `PageContext` via `requestId` matching, so racing VSCode requests no longer return "Frame not found" or blank the Variables panel

### Changed

- Minimum Lucee core version raised to **7.1.0.132**

## [3.0.0.6-SNAPSHOT] - 2026-05-09

### Fixed

- **[LDEV-6309](https://luceeserver.atlassian.net/browse/LDEV-6309)**: `StackOverflowError` when inspecting variables containing self-referential structs. `ValTracker.wrapperByObj` now uses identity-keyed weak references instead of `WeakHashMap`, so registering an object no longer triggers `StructImpl.hashCode()`'s value-walk on cyclic graphs.

## [3.0.0.5-SNAPSHOT] - 2026-04-23

### Fixed

- **[LDEV-6274](https://luceeserver.atlassian.net/browse/LDEV-6274)**: cfinclude frames now surface the included file's basename as the frame name, not the enclosing UDF's file
- **Native**: HTML dump/dumpAsJSON crash caused by `DEFAULT_RICH` typo in native path
- **Native**: DAP completions now suggest local + arguments scope variables
- **Native**: function breakpoint `stopped` event now reports reason `"function breakpoint"`; empty `setFunctionBreakpoints` response body; line-0 UDF frame included on function-entry suspend
- **Native**: custom DAP requests (e.g. `getApplicationSettings`) now routed to the currently-suspended PageContext; frame cache evicted per-thread on resume
- **Native**: `exceptionInfo` response now surfaces the CFML exception type
- **Agent**: background threads marked as daemon so they don't block JVM shutdown
- Bytecode transform failures now load un-instrumented class instead of killing the JVM
- `System.exit` call sites replaced with logging + continue — debugger can no longer crash the host JVM
- BIF calls in native mode use `ClassUtil.loadBIF` with short name, not full class path

### Changed

- Minimum Lucee core version raised to **7.1.0.100** (required for native exception breakpoints)
- Refactored `NativeLuceeVm` from reflection to loader API throughout
- Removed `Utils.terminate` / `Utils.unreachable` JVM-killers
- Removed hot-path debug `println` spam from agent mode

### Added

- **[LDEV-6282](https://luceeserver.atlassian.net/browse/LDEV-6282)**: Native-mode uncaught-exception breakpoints — debugger suspends on unhandled exceptions across cfm top-level, component methods, closures, cfthread join (throwOnError), and parallel arrayEach

## [3.0.0.4] - First Release 2026-03-26

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
