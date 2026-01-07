# AGENTS.md

Debug Adapter Protocol (DAP) debugger for Lucee CFML.

## Project Overview

This is a step debugger that lets you set breakpoints, inspect variables, and step through CFML code in VS Code.

Two modes:

- **Extension mode** (Lucee 7.1+) - Native debugger hooks, no Java agent required
- **Agent mode** (older Lucee) - Java agent with JDWP, bytecode instrumentation

## Repository Structure

```
extension-debugger/
├── source/java/           # Main Java source (extension + shared code)
├── agent/                 # Agent-specific build (shaded JAR)
├── vscode-client/         # VS Code extension (TypeScript)
├── test/                  # CFML integration tests
└── .github/workflows/     # CI - tests against Lucee 7.0 and 7.1
```

## Building

```bash
# Extension (.lex)
mvn clean install -Dgoal=install

# Agent (shaded JAR)
cd agent && mvn clean package
```

## Key Classes

- `DapServer` - DAP protocol handler (lsp4j)
- `ExtensionActivator` - Lucee startup hook (extension mode)
- `Agent` - Java agent premain (agent mode)
- `NativeLuceeVm` - 7.1+ native debugger integration
- `LuceeVm` - Agent mode with JDWP/bytecode instrumentation
- `DebugManager` - Breakpoint and stepping logic

## Testing

CFML integration tests run via GitHub Actions against:

- Lucee 7.1 (extension mode)
- Lucee 7.0, 6.2 (agent mode)

The test architecture uses two separate Lucee instances:

- **Debuggee**: Lucee Express (Tomcat) with luceedebug installed, DAP on port 10000, HTTP on 8888
- **Test runner**: `lucee/script-runner` instance running TestBox specs that connect to the debuggee via DAP

Tests set breakpoints, trigger HTTP requests to the debuggee, and verify the debugger stops at the right places.

### Debugging GitHub Actions Failures

When a workflow fails, download logs locally for inspection:

```bash
# Create test-output folder (already in .gitignore)
mkdir -p test-output

# Download all logs from a failed run
gh run view <RUN_ID> --repo lucee/extension-debugger --log > test-output/run-<RUN_ID>.log

# Or download artifacts (contains debuggee logs on failure)
gh run download <RUN_ID> --repo lucee/extension-debugger --dir test-output/

# Search logs locally
grep -E "ERROR|Exception|Failed" test-output/run-<RUN_ID>.log
```

Always use `test-output/` for workflow logs - it's gitignored so won't pollute the repo.

## Code Style

- Java 11+
- No Guava - use JDK or custom utils in `util/` package
- Tabs for indentation
- Fail fast - avoid defensive null checks
