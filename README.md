# Cpin

Paste 风格的本地原生 macOS 剪切板工具。用卡片整理复制过的文字、链接、代码和图片，随时搜索、置顶、粘贴。

**当前版本：v0.3.0 · macOS 13+ · SwiftUI + AppKit · 无第三方依赖**

Cpin 常驻菜单栏，不显示 Dock 图标，无需账号，也不上传剪切板内容。

## 功能

- **卡片历史**：记录纯文本、HTTP(S) 链接和 PNG/TIFF 图片；多行代码使用等宽字体，重复复制合并到原卡片。支持按内容或来源应用搜索。
- **单击使用**：授权后直接粘贴到呼出面板前的应用；未授权时改为复制，再手动粘贴。图钉独立操作，不会触发粘贴。
- **四方向、两种模式**：在顶部、底部、左侧或右侧显示，支持悬浮和贴边。上下横排、左右竖排，贴边内侧保留圆角，按所选方向滑入滑出，并遵循系统“减少动态效果”设置。面板出现在鼠标所在屏幕。
- **自定义保留数量**：默认最近 100 条，可设置任意正整数或不限制。置顶内容长期保留，不计入上限；降低上限会淘汰较早的未置顶记录。
- **本地存储管理**：查看磁盘占用、暂停记录、打开数据目录；确认后可清空未置顶内容，或一键删除全部历史、置顶内容和图片。

## 安装与首次权限

如果已获得 DMG，打开后将 `Cpin.app` 拖到 `Applications`，再从应用程序文件夹启动。也可以按下文从源码构建，安装生成的应用或 ZIP。

当前打包脚本使用 **ad-hoc 签名，尚未经过 Apple 公证**。首次打开若被 macOS 阻止，请确认来源可信，再到“系统设置 → 隐私与安全性”中允许打开。公开分发若需通过常规系统验证，仍需 Developer ID 签名及 Apple 公证。

首次启动会请求“辅助功能”权限，用于向目标应用发送粘贴快捷键。拒绝或暂不授权也能使用：单击卡片复制，收起面板后按 `⌘V` 手动粘贴。后续不会反复请求，可在偏好设置中重新授权。

## 快捷键

| 操作 | 方式 |
| --- | --- |
| 呼出 / 收起 | `⇧⌘V`，或点击菜单栏图标 |
| 选择卡片 | 横向面板 `←` / `→`；侧边面板 `↑` / `↓` |
| 使用卡片 | 单击内容、`Return`，或 `⌘1`–`⌘9`；未授权时复制 |
| 搜索 | `⌘F` |
| 收起 | `Esc` 或点击窗口外；有搜索内容时 `Esc` 先清除搜索 |
| 偏好设置 | `⌘,`、面板设置按钮，或右键菜单栏图标 |

卡片右上角图钉用于置顶；右键菜单提供复制、粘贴、置顶和删除。

## 源码构建与 DMG 打包

需要支持 Swift 5.9 或更新版本的 Apple Command Line Tools；可通过 `xcode-select --install` 安装，无需完整 Xcode。

```sh
git clone https://github.com/JohnMing143/cpin.git
cd cpin
./scripts/build.sh
open build/Cpin.app
```

默认构建当前 Mac 架构的 Release 应用，输出 `build/Cpin.app` 和 `build/Cpin.zip`。脚本会生成图标并执行本地签名验证。

```sh
# Debug 构建
./scripts/build.sh --debug

# Apple 芯片 + Intel 通用版
./scripts/build.sh --universal

# 构建通用版并打包 DMG
./scripts/package-dmg.sh

# 使用已有通用版 ZIP 重新封装
./scripts/package-dmg.sh --skip-build
```

通用版应用与 ZIP 位于 `build/universal/`，不会替换本机构建的 `build/Cpin.app`。当前版本 DMG 输出为 `build/Cpin-0.3.0-universal.dmg`，附带 `.sha256` 校验文件。DMG 包含应用、Applications 安装入口和中文使用说明；脚本会挂载检查签名、双架构和安装入口。

## 数据与隐私

应用不发起网络请求。历史保存在 `~/Library/Application Support/Cpin/`：

- `history.json`：文字与卡片元数据。
- `images/`：保存的图片，删除或淘汰对应卡片时一并移除。

数据未加密。分享的安装包只包含程序，不包含打包者的历史或设置；清理历史不会修改系统剪切板。清空后可能仍有少量空历史文件占用。

Cpin 跳过被来源应用标记为 concealed、transient 或 auto-generated 的内容，但不能识别所有未标记的敏感文字，需要时可暂停记录。启动前及暂停期间复制的内容不会补录。

目前不保留富文本格式或 Finder 文件列表。单条文本最多 1 MiB，图片最多 16 MiB / 6400 万像素；超限内容不收录。

## 开发验证

```sh
./scripts/check.sh
./scripts/check-panel.sh
```

`check.sh` 可直接使用 Command Line Tools，覆盖持久化、历史上限、磁盘统计、清理与错误处理，以及布局、设置和单击路由。剪切板及设置测试使用独立测试域，不触碰真实记录或系统剪切板。安装完整 Xcode 后也可运行 `swift test`。

`check-panel.sh` 需要已登录的 macOS 桌面，使用临时演示数据验证八种布局、滑动方向、焦点、快速反转及动画期间切换布局。运行时让测试窗口保持前台约 8 秒。

预览界面前先退出正在运行的 Cpin：

```sh
open build/Cpin.app --args --demo
```

演示模式使用临时数据，退出时删除；不读取、修改系统剪切板，也不请求权限。

## 项目结构

```text
Sources/Cpin/       菜单栏、剪切板监听、面板、卡片与偏好设置
Sources/CpinCore/   历史持久化、数据模型与面板布局计算
Tests/             核心、剪切板、布局、模型及原生窗口验证
Resources/         应用信息与 DMG 使用说明
scripts/           构建、图标生成、验证与 DMG 打包脚本
```
