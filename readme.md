# luceedebug

A step debugger for Lucee CFML, based on the [luceedebug](https://github.com/softwareCobbler/luceedebug) project by David Rogers.

![misc. features of a debug session indicating that luceedebug is a step debugger for Lucee.](assets/whatisit.png)

## How It Works

Luceedebug lets you set breakpoints in CFML code and step through execution. It works by inserting debug hooks into Lucee's compiled bytecode - when execution hits a breakpoint, the debugger pauses and lets you inspect variables, evaluate expressions, and step through code.

There are two ways to run luceedebug, depending on your Lucee version:

| | Lucee Extension | Java Agent |
|---|---|---|
| **Lucee version** | 7.1+ | Any |
| **Setup** | Install extension, set env vars | JVM startup flags |
| **JDK required** | No (JRE works) | Yes |
| **How it hooks in** | Built into Lucee | JDWP + bytecode instrumentation |

See [How It Works (Technical Details)](#how-it-works-technical-details) for more on the differences.

### Lucee Extension (Recommended, Lucee 7.1+)

The simplest and most efficient way to use luceedebug. No JVM configuration required, and significantly lower overhead than the agent approach:

- **Minimal overhead** when debugger not attached (hooks are JIT-compiled away)
- **No runtime instrumentation** - debug hooks are part of Lucee's bytecode generation, not re-instrumented at runtime
- **Works on JRE** - no JDK required
- **More features** - see [DAP Capabilities](#dap-capabilities) for extension-only features

**Setup:**

1. Install the extension via Lucee Admin, or deploy the `.lex` file to your extensions folder
2. Set environment variables:

   ```bash
   LUCEE_DAP_SECRET=your-secret-here
   LUCEE_DAP_PORT=10000
   ```

3. Restart Lucee
4. Connect your VS Code debugger (see [VS Code](#vs-code))

**Environment Variables:**

| Variable | Required | Description |
|----------|:--------:|-------------|
| `LUCEE_DAP_SECRET` | ✓ | Authentication secret (must match client config) |
| `LUCEE_DAP_PORT` | | Port for DAP server (default: 10000) |
| `LUCEE_DAP_BREAKPOINT` | | Set to `false` to disable breakpoint instrumentation |

Setting `LUCEE_DAP_BREAKPOINT=false` disables breakpoint support but keeps the DAP server running. This is useful if you only want console output streaming without the instrumentation overhead.

### Java Agent (Legacy)

For older Lucee versions or environments where the Lucee extension isn't suitable, you can run luceedebug as a Java agent. This requires JVM startup configuration.

See [JAVA_AGENT.md](JAVA_AGENT.md) for detailed setup instructions.

## IDE Integration

Luceedebug implements the [Debug Adapter Protocol (DAP)](https://microsoft.github.io/debug-adapter-protocol/), so it can work with any IDE that supports DAP. Currently we provide a VS Code extension, but the DAP server can be used with other editors.

### VS Code

The VS Code luceedebug extension is available on the VS Code Marketplace. Search for `luceedebug` in the extensions pane.

Add a debug configuration to your `.vscode/launch.json`:

```json5
{
    "type": "cfml",
    "request": "attach",
    "name": "Lucee Debugger",
    "hostName": "localhost",
    "port": 10000,
    "secret": "your-secret-here"
}
```

### VS Code Options

| Option | Description |
|--------|-------------|
| `pathTransforms` | Map IDE paths to server paths (see [Path Transforms](#path-transforms)) |
| `pathSeparator` | Path normalization: `auto` (default), `none`, `posix`, `windows` |
| `logColor` | Enable ANSI colors in debug log output (default: true) |
| `logLevel` | Log verbosity: `error`, `info`, `debug` (default: info) |

### DAP Options

These options control how the debug adapter behaves. They apply regardless of which IDE you're using.

| Option | Description |
|--------|-------------|
| `hostName` | DAP server host (default: localhost) |
| `port` | DAP server port (must match `LUCEE_DAP_PORT`) |
| `secret` | Authentication secret (must match `LUCEE_DAP_SECRET`, required for extension mode) |
| `consoleOutput` | Stream console output to debug console (extension mode only, default: false) |
| `evaluation` | Enable expression evaluation in console/watch/hover (default: true) |
| `logExceptions` | Log exceptions to the debug console (default: false) |

### DAP Capabilities

| Feature | Extension | Agent |
|---------|:---------:|:-----:|
| Line breakpoints | ✓ | ✓ |
| Conditional breakpoints | ✓ | ✓ |
| Function breakpoints | ✓ | ✗ |
| Exception breakpoints | ✓ | ✗ |
| Step in/out/over | ✓ | ✓ |
| Variable inspection | ✓ | ✓ |
| Set variable value | ✓ | ✗ |
| Watch expressions | ✓ | ✓ |
| Debug console evaluation | ✓ | ✓ |
| Hover evaluation | ✓ | ✓ |
| Completions (autocomplete) | ✓ | ✗ |
| Console output streaming | ✓ | ✗ |
| Breakpoint locations | ✓ | ✗ |
| Exception info | ✓ | ✗ |

### Path Transforms

`pathTransforms` maps between IDE paths and Lucee server paths. This is needed when your IDE sees files at different paths than Lucee does (e.g., Docker containers, remote servers).

For local debugging without containers, you may not need this - both your IDE and Lucee see files at the same path.

Example for Docker:

```json
"pathTransforms": [
  {
    "idePrefix": "/Users/dev/myproject",
    "serverPrefix": "/var/www"
  }
]
```

A breakpoint set on `/Users/dev/myproject/Application.cfc` maps to `/var/www/Application.cfc` on the server.

Multiple transforms can be specified - first match wins. Order them from most specific to least specific:

```json
"pathTransforms": [
  {
    "idePrefix": "/Users/dev/projects/subapp",
    "serverPrefix": "/var/www/subapp"
  },
  {
    "idePrefix": "/Users/dev/projects/app",
    "serverPrefix": "/var/www"
  }
]
```

## Features

### writeDump / serializeJSON

Right-click on a variable in the debug pane to get `writeDump(x)` or `serializeJSON(x)` output in an editor tab.

![writeDump context menu](assets/dumpvar-context-menu.png)

### Watch Expressions

Support for conditional breakpoints, watch expressions, and REPL evaluation.

![watch features being used](assets/watch.png)

**Notes:**

- Conditional breakpoints evaluate to "false" if they fail (not convertible to boolean, or throw an exception)
- Footgun: `x = 42` (assignment) vs `x == 42` (equality check) - be careful!
- Watch/REPL evaluation that triggers additional breakpoints may cause deadlocks

### Debug Breakpoint Bindings

If breakpoints aren't binding, use the command palette and run "luceedebug: show class and breakpoint info" to inspect what's happening.

## Building from Source

### Build the Extension (.lex)

```bash
./gradlew buildExtension
```

Output: `build/luceedebug-extension.lex`

### Build the Agent Jar

```bash
./gradlew shadowJar
```

Output: `luceedebug/build/libs/luceedebug.jar`

### Build the VS Code Extension

```bash
cd vscode-client
npm install
npm run build-dev-windows  # Windows
npm run build-dev-linux    # Mac/Linux
```

## Security Scanning

```bash
./gradlew dependencyCheckAnalyze
```

## How It Works (Technical Details)

Both modes work by inserting debug hooks into Lucee's compiled bytecode, but they do it differently:

### Lucee Extension Mode

Lucee 7.1+ has native support for debuggers, building on the [execution log](https://docs.lucee.org/recipes/execution-log.html) infrastructure. Lucee's bytecode includes debug hook points that are statically disabled by default - when a debugger registers, these hooks are enabled and call back to the debugger at each debug point.

This is efficient because:

- Debug hooks are compiled directly into Lucee's bytecode
- Hooks are JIT-compiled away when no debugger is attached
- No bytecode rewriting or class retransformation needed
- Works on any JRE (no JDK/JDWP required)

### Java Agent Mode

For older Lucee versions, luceedebug runs as a Java agent that instruments bytecode at runtime:

1. The agent connects to JDWP (Java Debug Wire Protocol) on the JVM
2. When Lucee loads a class, the agent intercepts and rewrites the bytecode to insert debug hooks
3. These hooks call back to the luceedebug agent when hit

This requires:

- A full JDK (not JRE) for JDWP support
- JVM startup flags to enable the agent and JDWP
- Bytecode instrumentation at class load time

**Note:** The bytecode instrumentation used with the agent can occasionally cause issues with complex CFCs, particularly those with many methods or deeply nested closures. 

The Lucee extension/native approach avoids these issues since the debug hooks are part of Lucee's own bytecode generation.
