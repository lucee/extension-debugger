# luceedebug - CFML Step Debugger for Lucee

Set breakpoints, inspect variables, and step through CFML code in VS Code.

![misc. features of a debug session indicating that luceedebug is a step debugger for Lucee.](https://raw.githubusercontent.com/lucee/extension-debugger/main/assets/whatisit.png)

## Quick Start

1. Install this extension from the VS Code Marketplace
2. Set up the debugger on your Lucee server (see [Server Setup](#server-setup))
3. Add a debug configuration to `.vscode/launch.json`:

```json
{
    "type": "cfml",
    "request": "attach",
    "name": "Lucee Debugger",
    "hostName": "localhost",
    "port": 10000,
    "secret": "your-secret-here"
}
```

4. Start debugging (F5)

## Server Setup

The debugger server runs on your Lucee instance. There are two modes depending on your Lucee version:

### Lucee Extension (Recommended, Lucee 7.1+)

Install the `.lex` extension via Lucee Admin or deploy it to your extensions folder, then set environment variables:

```bash
LUCEE_DAP_SECRET=your-secret-here
LUCEE_DAP_PORT=10000
```

### Java Agent (Lucee 6.x / 7.0)

For older Lucee versions, luceedebug runs as a Java agent with JDWP. See the [Java Agent docs](https://github.com/lucee/extension-debugger/blob/main/JAVA_AGENT.md) for setup instructions.

## Configuration Options

| Option | Description |
|--------|-------------|
| `hostName` | DAP server host (required) |
| `port` | DAP server port (default: 10000) |
| `secret` | Authentication secret (must match `LUCEE_DAP_SECRET` on server) |
| `pathTransforms` | Map IDE paths to server paths (see [Path Transforms](#path-transforms)) |
| `pathSeparator` | Path normalization: `auto` (default), `none`, `posix`, `windows` |
| `evaluation` | Enable expression evaluation in console/watch/hover (default: true) |
| `consoleOutput` | Stream console output to debug console (extension mode only, default: false) |
| `logExceptions` | Log exceptions to the debug console (default: false) |
| `logLevel` | Log verbosity: `error`, `info`, `debug` (default: info) |
| `logColor` | Enable ANSI colors in debug log output (default: true) |

## Path Transforms

`pathTransforms` maps between IDE paths and Lucee server paths. This is needed when your IDE sees files at different paths than Lucee does (e.g. Docker containers, remote servers).

For local debugging without containers, you may not need this.

Example for Docker:

```json
"pathTransforms": [
  {
    "idePrefix": "/Users/dev/myproject",
    "serverPrefix": "/var/www"
  }
]
```

Multiple transforms can be specified - first match wins. Order from most specific to least specific.

## Features

### Breakpoints

Line breakpoints, conditional breakpoints, function breakpoints (extension mode), and exception breakpoints (extension mode).

### Variable Inspection

Inspect all scopes - local, arguments, variables, request, session, application, and more.

### writeDump / serializeJSON

Right-click on a variable in the debug pane to get `writeDump(x)` or `serializeJSON(x)` output in an editor tab.

![writeDump context menu](https://raw.githubusercontent.com/lucee/extension-debugger/main/assets/dumpvar-context-menu.png)

### Watch Expressions

Support for watch expressions and REPL evaluation in the debug console.

![watch features being used](https://raw.githubusercontent.com/lucee/extension-debugger/main/assets/watch.png)

**Notes:**

- Conditional breakpoints evaluate to "false" if they fail (not convertible to boolean, or throw an exception)
- `x = 42` (assignment) vs `x == 42` (equality check) - be careful in conditions!
- Watch/REPL evaluation that triggers additional breakpoints may cause deadlocks

### Debug Breakpoint Bindings

If breakpoints aren't binding, open the command palette and run **"luceedebug: show class and breakpoint info"** to inspect what's happening.

## Capabilities

| Feature | Extension (7.1+) | Agent (6.x/7.0) |
|---------|:---------:|:-----:|
| Line breakpoints | Yes | Yes |
| Conditional breakpoints | Yes | Yes |
| Function breakpoints | Yes | No |
| Exception breakpoints | Yes | No |
| Step in/out/over | Yes | Yes |
| Variable inspection | Yes | Yes |
| Set variable value | Yes | No |
| Watch expressions | Yes | Yes |
| Debug console evaluation | Yes | Yes |
| Hover evaluation | Yes | Yes |
| Completions (autocomplete) | Yes | No |
| Console output streaming | Yes | No |
| Breakpoint locations | Yes | No |
| Exception info | Yes | No |

## Links

- [GitHub Repository](https://github.com/lucee/extension-debugger)
- [Java Agent Setup](https://github.com/lucee/extension-debugger/blob/main/JAVA_AGENT.md)
- [Issue Tracker](https://github.com/lucee/extension-debugger/issues)
