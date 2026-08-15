# DeepSeek Harness Launcher

<div align="center">

![DeepSeek Harness Launcher 图标](assets/app.png)

### 面向 DeepSeek Harness Web UI 的轻量原生 Windows 启动器

[![CI](https://github.com/zboheng53-jpg/deepseek-harness-launcher/actions/workflows/ci.yml/badge.svg)](https://github.com/zboheng53-jpg/deepseek-harness-launcher/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6.svg?logo=windows)]()

[English](README.md) | 中文文档

</div>

> [!IMPORTANT]
> 本项目是非官方社区项目，与 DeepSeek 不存在隶属、维护或背书关系。DeepSeek 名称和视觉标识的权利归各自权利人所有，此处仅用于说明与 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的兼容性。

它不引入 Electron/Tauri，不 fork Harness，只为 Windows 增加静默桌面启动、单实例、健康检查、安全进程跟踪、诊断和可预测的版本选择。

## 核心特性

- 通过桌面快捷方式和 VBScript 静默启动，不闪现控制台窗口。
- 已有健康实例时直接复用；命名 mutex 防止连续双击产生重复服务。
- 3080 端口若被其他程序占用会明确报错，不会误认为 Harness。
- 只停止已跟踪或可明确识别的 `dsh web` 进程，并防范 PID 复用。
- 配置、状态和轮转日志统一保存在 `%LOCALAPPDATA%\DeepSeekHarnessLauncher`，与程序文件分离。
- 只支持结构化的 `npm` / `source` 模式，JSON 配置不能注入任意 Shell 命令。
- npm 模式固定到明确验证过的 Harness 版本，上游更新不会在用户不知情时改变实际程序。
- 提供中英文界面、一键诊断、Windows 行为测试及 Release SHA-256 校验和。

## 安装

从 [Releases](https://github.com/zboheng53-jpg/deepseek-harness-launcher/releases) 下载 ZIP 和 `SHA256SUMS.txt`，校验哈希后完整解压，再双击 `install.bat`。

默认 `npm` 模式要求：

- Windows 10 或 11
- Windows PowerShell 5.1 或更高版本
- Node.js `^22.19.0` 或 `>=24.0.0`
- `PATH` 中存在 `npx`

如需使用本地上游源码仓库，可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 `
  -ProjectPath "C:\src\deepseek-harness"
```

`source` 模式还要求安装 `pnpm`，且目标 `package.json` 定义了 `dsh` 脚本。

## 使用

- 双击桌面 **DeepSeek Harness** 图标启动或重新打开 Web UI。
- 运行 `stop.bat` 安全停止此启动器管理的服务。
- 运行 `diagnose.bat` 生成 `%TEMP%\deepseek-harness-launcher-diagnostics.txt`。
- 运行 `uninstall.bat` 删除快捷方式并停止服务；用户配置和日志会保留。

## 配置

仓库中的 [config.default.json](config.default.json) 只是模板。安装后真正使用的配置位于：

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

| 配置项 | 含义 |
| --- | --- |
| `mode` | `npm` 启动指定的精确包版本；`source` 在 `projectPath` 中执行 `pnpm dsh web`。 |
| `projectPath` | 仅 `source` 模式需要，必须指向本地 DeepSeek Harness 源码仓库。 |
| `packageVersion` | npm 精确版本；公开默认值必须与 `compatibility.json` 一致。 |
| `extraArgs` | 直接作为参数传给 `dsh web`，不会交给 Shell 求值。 |
| `host` / `port` | 健康检查和浏览器打开地址；如果通过参数更改 Harness 监听地址，需要同步修改。 |
| `autoOpenBrowser` | 服务通过身份健康检查后自动打开默认浏览器。 |
| `timeoutSeconds` | 1–900 秒的冷启动超时时间。 |

安装器会迁移旧版本放在仓库根目录的 `config.json`。新版运行时不会向解压目录写入用户状态。

## 兼容策略

[compatibility.json](compatibility.json) 记录启动器最后验证的 Harness 版本。上游明确处于 developer preview，并可能发生破坏性变更，因此 npm 模式默认使用精确版本而不是 `latest`。更新该版本必须重新执行行为测试并发布新的启动器版本。

| 启动器 | 已验证 Harness | Node.js |
| --- | --- | --- |
| `0.1.x` | `0.1.0-rc.5` | `^22.19.0` 或 `>=24.0.0` |

## 验证与贡献

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1 -Behavior
```

测试既检查发行包完整性，也会使用假本地服务覆盖冷启动、热激活、端口冲突、安全停止和超时清理。参与贡献或报告安全问题前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [SECURITY.md](SECURITY.md)。

## 许可证

启动器代码使用 [MIT License](LICENSE)。该许可证不授予任何第三方名称或 Logo 的使用权。
