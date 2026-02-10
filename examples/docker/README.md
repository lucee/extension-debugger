# Docker Example

Debug Lucee CFML running in Docker with luceedebug.

## Quick Start

Install the vscode extension `https://marketplace.visualstudio.com/items?itemName=DavidRogers.luceedebug`

```bash
docker compose up
```

- Lucee: http://localhost:8888
- DAP debugger: port 10000

Open this folder in VS Code, install the `luceedebug` extension, set a breakpoint in [app/index.cfm](app/index.cfm) and hit F5.

## How It Works

The Lucee 7.1+ Docker image ships with the debugger extension pre-installed. Two env vars enable it:

- `LUCEE_DAP_SECRET` - authentication secret (must match your launch.json)
- `LUCEE_DAP_PORT` - DAP server port
- `LUCEE_DAP_HOST` - bind address (`0.0.0.0` for Docker, defaults to `localhost`)

The `pathTransforms` in [.vscode/launch.json](.vscode/launch.json) maps your local `app/` folder to `/var/www` inside the container.
