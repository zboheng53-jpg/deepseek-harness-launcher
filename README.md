# DeepSeek Harness Launcher

<div align="center">

![DeepSeek Harness Launcher icon](assets/app.png)

### The lightweight native Windows launcher for the DeepSeek Harness Web UI

[![CI](https://github.com/zboheng53-jpg/deepseek-harness-launcher/actions/workflows/ci.yml/badge.svg)](https://github.com/zboheng53-jpg/deepseek-harness-launcher/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6.svg?logo=windows)]()

English | [中文文档](README.zh.md)

</div>

> [!IMPORTANT]
> This is an unofficial community project. It is not affiliated with, maintained by, or endorsed by DeepSeek. DeepSeek names and visual marks belong to their respective owners and are used only to identify compatibility with [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

DeepSeek Harness Launcher adds a silent desktop shortcut, single-instance startup, health checks, safe process tracking, diagnostics, and predictable version selection without bundling a browser engine or forking Harness.

## Highlights

- Silent native Windows launch through a `.lnk` and VBScript wrapper—no console flash.
- Reuses a healthy Harness instance and prevents duplicate cold starts with a named mutex.
- Refuses to treat an unrelated service on port 3080 as Harness.
- Stops only tracked or positively identified `dsh web` processes and guards against PID reuse.
- Stores configuration, state, and rotating logs outside the program folder under `%LOCALAPPDATA%\DeepSeekHarnessLauncher`.
- Uses structured `npm`/`source` configuration; JSON cannot supply an arbitrary shell command.
- Pins npm mode to an explicitly tested Harness version so a future upstream release cannot silently change an installed launcher.
- Includes bilingual dialogs, a one-click diagnostic report, Windows CI behavior tests, and SHA-256 release checksums.

## Install

Download the ZIP and `SHA256SUMS.txt` from [Releases](https://github.com/zboheng53-jpg/deepseek-harness-launcher/releases), verify the checksum, extract the complete folder, and double-click `install.bat`.

The default `npm` mode requires:

- Windows 10 or 11
- Windows PowerShell 5.1 or later
- Node.js `^22.19.0` or `>=24.0.0`
- `npx` in `PATH`

For a local upstream checkout, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 `
  -ProjectPath "C:\src\deepseek-harness"
```

Source mode also requires `pnpm` and a checkout whose `package.json` defines the `dsh` script.

## Use

- Double-click the desktop **DeepSeek Harness** shortcut to launch or reopen the Web UI.
- Run `stop.bat` to stop the server managed by this launcher.
- Run `diagnose.bat` to create `%TEMP%\deepseek-harness-launcher-diagnostics.txt`.
- Run `uninstall.bat` to remove the shortcut and stop the server. Configuration and logs are preserved.

## Configuration

The tracked [config.default.json](config.default.json) is a template. Installation creates the user-owned file at:

```text
%LOCALAPPDATA%\DeepSeekHarnessLauncher\config.json
```

```json
{
  "schemaVersion": 1,
  "mode": "npm",
  "projectPath": "",
  "packageVersion": "0.1.0-rc.5",
  "extraArgs": [],
  "port": 3080,
  "host": "127.0.0.1",
  "autoOpenBrowser": true,
  "timeoutSeconds": 90
}
```

| Setting | Meaning |
| --- | --- |
| `mode` | `npm` runs the exact `packageVersion`; `source` runs `pnpm dsh web` in `projectPath`. |
| `projectPath` | Required only for a local DeepSeek Harness checkout in `source` mode. |
| `packageVersion` | Exact npm package version; the public default matches `compatibility.json`. |
| `extraArgs` | Additional argument strings passed directly to `dsh web`, without shell evaluation. |
| `host` / `port` | Address used for health checks and browser opening. If Harness is configured to listen elsewhere, keep these values in sync. |
| `autoOpenBrowser` | Opens the default browser after a verified health check. |
| `timeoutSeconds` | Startup deadline from 1 to 900 seconds. |

Legacy repository-local `config.json` is migrated during installation. Runtime data is never written to the extracted program directory.

## Compatibility policy

[compatibility.json](compatibility.json) records the last Harness version tested by this launcher. DeepSeek Harness describes itself as a developer preview with compatibility-breaking changes, so npm mode uses that exact version rather than `latest`. Updating it requires behavior verification and a launcher release.

| Launcher | Tested Harness | Node.js |
| --- | --- | --- |
| `0.1.x` | `0.1.0-rc.5` | `^22.19.0` or `>=24.0.0` |

## Verify and contribute

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1 -Behavior
```

The suite validates package integrity and exercises cold start, hot activation, port conflicts, safe stop, and timeout cleanup against a fake local server. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

Launcher code is available under the [MIT License](LICENSE). This license does not grant rights to third-party names or logos.
