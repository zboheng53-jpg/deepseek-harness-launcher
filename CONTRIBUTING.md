# Contributing

Thanks for helping improve DeepSeek Harness Launcher. This is an unofficial Windows-only companion to the upstream DeepSeek Harness project.

## Before opening a change

- Use GitHub Discussions on the upstream project for DeepSeek Harness product questions.
- Use this repository for launcher installation, startup, shutdown, diagnostics, and Windows integration issues.
- For vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Development

The launcher targets Windows 10/11 and Windows PowerShell 5.1. Keep scripts compatible with that runtime and avoid adding a GUI framework or persistent service dependency.

Run the complete verification suite before submitting a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1 -Behavior
```

Pull requests should explain the user impact, update both English and Chinese documentation when behavior changes, and avoid committing `%LOCALAPPDATA%` configuration or logs.
