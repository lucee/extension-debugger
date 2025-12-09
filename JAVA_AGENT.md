# Java Agent Setup

This document covers running luceedebug as a Java agent. This is the legacy approach - for Lucee 6.2+, consider using the [native extension](README.md) instead.

## Requirements

- JDK 11+ (not JRE - a common error is `java.lang.NoClassDefFoundError: com/sun/jdi/Bootstrap`)
- Building requires JDK 17+

## Download

Built jars are available via GitHub releases:

https://github.com/lucee/extension-debugger/releases/latest

Or build from source:

```bash
./gradlew shadowJar
```

Output: `luceedebug/build/libs/luceedebug.jar`

## JVM Configuration

Add the following to your Java invocation. Tomcat users can use `setenv.sh` or `setenv.bat`.

```bash
-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=localhost:9999

-javaagent:/abspath/to/luceedebug.jar=jdwpHost=localhost,jdwpPort=9999,debugHost=0.0.0.0,debugPort=10000,jarPath=/abspath/to/luceedebug.jar
```

### agentlib (JDWP)

Configures JDWP, the lower-level Java debugging protocol that the luceedebug agent connects with.

| Parameter | Value | Notes |
|-----------|-------|-------|
| `transport` | `dt_socket` | Use verbatim |
| `server` | `y` | Use verbatim |
| `suspend` | `n` | Use verbatim |
| `address` | `localhost:9999` | Change only if port 9999 is in use |

**Note:** The VS Code debugger connects to luceedebug, not JDWP directly, so these settings rarely need customising.

### javaagent (luceedebug)

Configures the luceedebug agent itself.

| Parameter | Description |
|-----------|-------------|
| `/abspath/to/luceedebug.jar` | Absolute path to the agent jar. Must match your environment. |
| `jdwpHost` | Host where JDWP is listening. Must match `agentlib`'s `address`. |
| `jdwpPort` | Port where JDWP is listening. Must match `agentlib`'s `address`. |
| `debugHost` | Interface for the debugger to listen on. See [Network Configuration](#network-configuration). |
| `debugPort` | Port for VS Code to connect to. |
| `jarPath` | Must be identical to the first token. Required for loading instrumentation. |

**Why specify the jar path twice?** The first tells the JVM which jar to use as a Java agent; the second tells the agent where to load debugging instrumentation from. There's no obvious way to get "the current jar path" from an agent's `premain`.

## Network Configuration

### Local Development

For local debugging without containers:

```bash
-javaagent:/path/to/luceedebug.jar=jdwpHost=localhost,jdwpPort=9999,debugHost=localhost,debugPort=10000,jarPath=/path/to/luceedebug.jar
```

### Docker / Containers

When Lucee runs in a container, `debugHost` **must** be `0.0.0.0` (listen on all interfaces):

```bash
-javaagent:/path/to/luceedebug.jar=jdwpHost=localhost,jdwpPort=9999,debugHost=0.0.0.0,debugPort=10000,jarPath=/path/to/luceedebug.jar
```

**Security Warning:** Don't use `0.0.0.0` on publicly accessible servers without proper firewall rules - it exposes the debugger to the network.

### Remote Servers

On remote servers, set `debugHost` to a specific interface IP, or use `0.0.0.0` with appropriate firewall rules to restrict access.

## VS Code Configuration

See the main [README.md](README.md#vs-code-configuration) for VS Code `launch.json` configuration.

For agent mode, you don't need the `secret` field - that's only for native extension mode.

```json
{
    "type": "cfml",
    "request": "attach",
    "name": "Lucee Debugger",
    "hostName": "localhost",
    "port": 10000
}
```

## Tomcat Example

### Linux/Mac (setenv.sh)

```bash
#!/bin/bash
CATALINA_OPTS="$CATALINA_OPTS -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=localhost:9999"
CATALINA_OPTS="$CATALINA_OPTS -javaagent:/opt/luceedebug/luceedebug.jar=jdwpHost=localhost,jdwpPort=9999,debugHost=0.0.0.0,debugPort=10000,jarPath=/opt/luceedebug/luceedebug.jar"
```

### Windows (setenv.bat)

```batch
set CATALINA_OPTS=%CATALINA_OPTS% -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=localhost:9999
set CATALINA_OPTS=%CATALINA_OPTS% -javaagent:C:\luceedebug\luceedebug.jar=jdwpHost=localhost,jdwpPort=9999,debugHost=0.0.0.0,debugPort=10000,jarPath=C:\luceedebug\luceedebug.jar
```

## Troubleshooting

### NoClassDefFoundError: com/sun/jdi/Bootstrap

You're running a JRE instead of a JDK. Install a full JDK.

### Connection refused

- Check that JDWP started successfully (look for "Listening for transport dt_socket at address: 9999" in logs)
- Verify `jdwpHost`/`jdwpPort` match the `agentlib` address
- Check firewall rules if connecting remotely

### Breakpoints not binding

Use the VS Code command palette and run "luceedebug: show class and breakpoint info" to see what's happening.
