# 息刻 Xike

息刻是一款面向 macOS 26 及以上版本的原生专注工具：通过任务、专注记录、随机微休息与长休息建立可持续的工作节律。App 使用 Swift 6、SwiftUI、SwiftData 与 AppKit，不包含第三方依赖、账户、网络服务或遥测。

## 功能

- 轻量任务清单：标签、预计时长、完成、归档、搜索与筛选。
- 专注会话绑定任务或临时目标，并记录一句复盘。
- 独立任务/历史窗口、菜单栏控制、系统全局快捷键。
- 类似系统 HUD 的 Liquid Glass 休息浮层，可关闭并选择中央或屏幕四角。
- 主窗口会随窗口宽度自动切换双栏或单栏布局。
- Shortcuts、Siri/Spotlight App Intents 与专注模式节律过滤器。
- 睡眠/锁屏自动暂停、异常退出恢复、通知与多显示器微休息浮层。

## 开发环境

- macOS 26+
- Swift 6.4+
- 完整 Xcode，且包含 macOS 26 或更高版本 SDK
- Bundle Identifier：`com.zhanglishan.Xike`
- App Sandbox：已通过 `Xike.entitlements` 启用

当前机器已安装 `/Applications/Xcode-beta.app`，统一脚本会自动检测完整 Xcode；若活动开发目录仍是 Command Line Tools，也能使用检测到的 Xcode 构建。只有在找不到完整 Xcode 时才回退到 SwiftPM，并生成临时签名的 `dist/Xike.app`。完整功能、测试、Shortcuts 和 Developer ID 发布均以 Xcode 工程构建为准。

安装 Xcode 后，在终端执行：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version
```

如果 Xcode 安装在其他位置，请替换上面的 Developer 路径。

## 构建与运行

Codex 的 Run 按钮以及本地开发都使用同一个入口：

```bash
./script/build_and_run.sh
```

生成供自己安装使用的优化版 App：

```bash
./script/build_and_run.sh --package
```

成功后产物位于 `dist/Xike.app`。可把它拖到「应用程序」文件夹后从 Launchpad 或 Spotlight 打开；该包使用本机 ad-hoc 签名，仅适合本机使用，不适合分享给他人。

可用模式：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

- 默认模式：结束旧进程、构建并打开最新 App。
- `--verify`：打开后验证 `Xike` 进程是否存在。
- `--package`：使用 Release 配置构建，将 App 复制到 `dist/Xike.app`，并进行本机 ad-hoc 签名和完整性校验。
- `--debug`：先从 `.app` bundle 启动，再让 LLDB 附加到进程，避免裸二进制缺少 bundle 身份。
- `--logs`：打开 App 并查看它的统一日志。
- `--telemetry`：只查看 subsystem `com.zhanglishan.Xike` 的结构化事件。

测试采用 Swift Testing；当前 Command Line Tools 不包含 `Testing` 模块，请先安装并切换到完整 Xcode，再运行：

```bash
swift test
```

安装完整 Xcode 后也可运行：

```bash
xcodebuild -project Xike.xcodeproj -scheme Xike test
```

## 签名与分发

SwiftPM 开发构建由脚本使用 ad-hoc 身份 `-` 签名，并带上沙盒 entitlement，适合本机验证，不适合分发。

准备分享正式版本时：

1. 在 Xcode 打开 `Xike.xcodeproj`，选择 Xike target 的 **Signing & Capabilities**。
2. 保持 **App Sandbox** 开启，选择自己的 Apple Developer Team；若 `com.zhanglishan.Xike` 不属于该团队，请改成团队拥有的唯一 Bundle Identifier。
3. 对外分发选择 **Product > Archive**，在 Organizer 中选择 **Distribute App > Developer ID**，完成 Developer ID Application 签名与 Apple 公证。
4. 导出后使用 `codesign --verify --deep --strict Xike.app` 和 `spctl --assess --type execute Xike.app` 做最终验证。

Mac App Store 分发还需在对应 App ID 和 App Store Connect 记录中使用完全一致的 Bundle Identifier。不要把 Developer ID 证书、私钥或公证凭据提交到仓库。

Developer ID 发布使用本机钥匙串中的证书和 `notarytool` profile：

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
TEAM_ID='TEAMID' ./script/release.sh archive

NOTARY_PROFILE='xike-notary' ./script/release.sh notarize
```

脚本不会读取仓库内的密钥文件。公证完成后会执行 stapling、签名、entitlements、Gatekeeper 和票据验证。隐私承诺见 [PRIVACY.md](PRIVACY.md)，版本内容见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。
