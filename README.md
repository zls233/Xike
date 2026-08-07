# 息刻 Xike

息刻是一款面向 macOS 26 及以上版本的原生专注工具：在 90 分钟专注周期中随机提醒 10 秒微休息，周期结束后进入 20 分钟长休息。App 使用 Swift 6、SwiftUI、SwiftData（完整 Xcode 构建）与 AppKit 浮层，不包含第三方依赖、账户、网络服务或遥测。

## 开发环境

- macOS 26+
- Swift 6.4+
- 完整 Xcode，且包含 macOS 26 或更高版本 SDK
- Bundle Identifier：`com.zhanglishan.Xike`
- App Sandbox：已通过 `Xike.entitlements` 启用

当前机器的活动开发目录是 `/Library/Developer/CommandLineTools`，尚未选择完整 Xcode，因此 `xcodebuild` 暂不可用。统一脚本会先尝试 SwiftPM 回退构建，并在链接成功时生成、复制资源及临时签名 `dist/Xike.app`。但当前 beta Command Line Tools 缺少完整 SwiftUI 音频链接依赖，实际运行本 App 仍需安装完整 Xcode。SwiftPM 路径使用 Codable JSON 持久化；安装完整 Xcode 后，脚本会优先构建 Xcode 工程并启用 SwiftData 路径。

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

可用模式：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

- 默认模式：结束旧进程、构建并打开最新 App。
- `--verify`：打开后验证 `Xike` 进程是否存在。
- `--debug`：使用 LLDB 启动最新构建产物。
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
