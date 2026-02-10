# Docker Example

Debug Lucee CFML running in Docker with luceedebug.

## Quick Start

```bash
docker compose up
```

- Lucee: http://localhost:8888
- DAP debugger: port 10000

## VS Code

Install the [LuceeDebug](https://marketplace.visualstudio.com/items?itemName=DavidRogers.luceedebug) VS Code extension.

- Open this folder in VS Code
- Set a breakpoint in [app/index.cfm](app/index.cfm)
- Press F5 (Run / Start Debugging)
- Switch to the debug console view
- Open [http://localhost:8888](http://localhost:8888) in a browser

The VS Code extension adds context menu commands (writeDump, serializeJSON, getMetadata) and hover evaluation for CFML variables. All core debugging features (breakpoints, stepping, variable inspection) are standard DAP.

## Other DAP Clients

Luceedebug uses the [Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/), so any DAP client that can connect via TCP socket should work. The key requirement is that the `attach` request must include `secret` in its arguments.

### Neovim (nvim-dap)

```lua
local dap = require("dap")

dap.adapters.cfml = {
  type = "server",
  host = "localhost",
  port = 10000,
}

dap.configurations.cfml = {
  {
    type = "cfml",
    request = "attach",
    name = "Lucee Docker Debugger",
    secret = "my-secret",
    pathTransforms = {
      {
        idePrefix = "${workspaceFolder}/app",
        serverPrefix = "/var/www",
      },
    },
  },
}
```

### IntelliJ (LSP4IJ plugin)

Install the [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) plugin, then create a DAP Run/Debug configuration:

- **Server tab**: Connect via socket to `localhost:10000` (no command needed, the server is already running)
- **Configuration tab**: Set the JSON to:

```json
{
  "request": "attach",
  "secret": "my-secret",
  "pathTransforms": [
    {
      "idePrefix": "${workspaceFolder}/app",
      "serverPrefix": "/var/www"
    }
  ]
}
```

## How It Works

The Lucee 7.1+ Docker image is used, with with the debugger extension being installed via an env var:

`LUCEE_EXTENSIONS: org.lucee:debugger-extension:3.0.0.1-SNAPSHOT`.

Three env vars enable it:

- `LUCEE_DAP_SECRET` - authentication secret (must match your launch.json)
- `LUCEE_DAP_PORT` - DAP server port
- `LUCEE_DAP_HOST` - bind address (`0.0.0.0` for Docker, defaults to `localhost`)
- `LUCEE_DEBUGGER_DEBUG` - set to `true` for verbose debug logging to the console

The `pathTransforms` in [.vscode/launch.json](.vscode/launch.json) maps your local `app/` folder to `/var/www` inside the container.
