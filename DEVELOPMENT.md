# 开发与构建

这份文档面向想从源码构建、修改或验证 Cpin 的人。使用说明见 [README.md](README.md)。

## 环境

需要 macOS 13 或更新版本，以及 Swift 5.9 或更新版本。安装 Apple Command Line Tools 即可，不需要完整 Xcode：

```sh
xcode-select --install
```

项目没有第三方依赖。

## 构建应用

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
```

通用版应用和 ZIP 位于 `build/universal/`，不会覆盖本机构建的 `build/Cpin.app`。

## 打包 DMG

```sh
# 构建通用版并打包 DMG
./scripts/package-dmg.sh

# 使用已有通用版 ZIP 重新封装
./scripts/package-dmg.sh --skip-build
```

输出为 `build/Cpin-0.3.0-universal.dmg`，文件名随 `Resources/Info.plist` 里的版本变化，同时生成 `.sha256` 校验文件。DMG 包含应用、Applications 安装入口和中文使用说明；脚本会挂载检查签名、双架构和安装入口。

## 签名与分发

打包脚本使用 ad-hoc 签名，没有经过 Apple 公证。用户首次打开时，需要在“系统设置 → 隐私与安全性”中放行。公开分发若希望省掉这一步，需要 Developer ID 签名和 Apple 公证。

## 运行验证

```sh
./scripts/check.sh
./scripts/check-panel.sh
```

`check.sh` 只依赖 Command Line Tools，覆盖持久化、历史上限、磁盘统计、清理与错误处理，以及布局、设置和单击路由。剪切板及设置测试使用独立测试域，不会碰真实记录或系统剪切板。安装完整 Xcode 后也可以运行 `swift test`。

`check-panel.sh` 需要已登录的 macOS 桌面，使用临时演示数据验证八种布局、滑动方向、焦点、快速反转，以及动画期间切换布局。运行时测试窗口会保持在前台，约 8 秒。

## 预览界面

先退出正在运行的 Cpin：

```sh
open build/Cpin.app --args --demo
```

演示模式使用临时数据，退出时删除。它不读取或修改系统剪切板，也不请求权限。

## 项目结构

```text
Sources/Cpin/       菜单栏、剪切板监听、面板、卡片与偏好设置
Sources/CpinCore/   历史持久化、数据模型与面板布局计算
Tests/              核心、剪切板、布局、模型及原生窗口验证
Resources/          应用信息与 DMG 使用说明
scripts/            构建、图标生成、验证与 DMG 打包脚本
```
