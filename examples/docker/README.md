# Docker Example

Debug Lucee CFML running in Docker with luceedebug.

## Quick Start

```bash
docker compose up
```

- Lucee: http://localhost:8888
- DAP debugger: port 10000

Install the [LuceeDebug](https://marketplace.visualstudio.com/items?itemName=DavidRogers.luceedebug) vscode extension, 

## Run the demo

- Open this folder in VS Code
- Set a breakpoint in [app/index.cfm](app/index.cfm)
- Press F5 (Run / Start Debugging)
- Switch the to debug console view
- Open [http://localhost:8888](http://localhost:8888) in a browser

## How It Works

The Lucee 7.1+ Docker image is used, with with the debugger extension being installed via an env var:

`LUCEE_EXTENSIONS: org.lucee:debugger-extension:3.0.0.1-SNAPSHOT`.

Three env vars enable it:

- `LUCEE_DAP_SECRET` - authentication secret (must match your launch.json)
- `LUCEE_DAP_PORT` - DAP server port
- `LUCEE_DAP_HOST` - bind address (`0.0.0.0` for Docker, defaults to `localhost`)

The `pathTransforms` in [.vscode/launch.json](.vscode/launch.json) maps your local `app/` folder to `/var/www` inside the container.
