# Security Policy

## Supported versions

Security fixes are provided for the latest published beta release and the default branch.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting flow under **Security → Report a vulnerability**. Do not include exploit details, credentials, or personal log data in a public issue. If private reporting is unavailable, open a minimal issue asking the maintainer for a private contact channel without disclosing technical details.

Reports should include the affected launcher version, Windows and PowerShell versions, reproduction steps, and the security impact. You can generate non-secret environment details with `diagnose.bat`; review the output before sharing it because configuration paths may contain your Windows user name.

The launcher only accepts structured `npm` or `source` configuration. Treat local configuration and `extraArgs` as trusted user input, and only install archives whose SHA-256 digest matches the release's `SHA256SUMS.txt`.
