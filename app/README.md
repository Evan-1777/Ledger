# Ledger Android 客户端

Flutter + Material 3 客户端，复用仓库根目录 Go 服务的 HTTP API。Android 为交付面，Web 构建用于本地自检。

## 环境

- Flutter 3.44.6，Dart 3.12.2
- Android 构建与发布由 GitHub Actions 完成；本机不安装 JDK、Android SDK、Gradle 或 adb
- 依赖：provider、http、shared_preferences、flutter_secure_storage、intl

## 本地运行

在仓库根目录准备一份临时数据库并启动后端，允许 Web 自检来源：

```bash
LEDGER_DB_PATH=/tmp/ledger.db \
LEDGER_ADMIN_PASSWORD=ledger-test-pass \
LEDGER_CORS_ORIGIN=http://localhost:5174 \
go run ./cmd/server
```

另开终端启动 Flutter Web 调试服务：

```bash
cd app
export PATH=/path/to/flutter/bin:$PATH
export PUB_CACHE=$PWD/../.pub-cache
flutter pub get
flutter run -d web-server --web-port 5174
```

打开 `http://localhost:5174`，服务器地址填 `http://localhost:8080`，密码使用启动后端时设置的 `LEDGER_ADMIN_PASSWORD`。debug 构建允许本地明文 HTTP；release 构建只接受 HTTPS。

## 检查与构建

```bash
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

仓库根目录的 `make app-format`、`make app-analyze`、`make app-test`、`make app-web` 分别封装格式检查、`pub get + analyze`、测试与 Web 构建。若 `dart` 不在 PATH，使用 `make app-format DART=/path/to/dart`。

## 发布

`.github/workflows/android.yml` 在 `app/**` 变更时运行格式检查、静态分析、单元/Widget 测试并构建 APK。

配置以下 Secrets 后产出签名 release APK（artifact：`ledger-release`）：

| Secret | 含义 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

未配置 `ANDROID_KEYSTORE_BASE64` 时产出 debug 验收包（artifact：`ledger-debug`）。`key.properties` 与 keystore 只在 CI 临时目录生成，构建结束即删除。

### 0.1.0 一次性签名与 Release

`.github/workflows/android-release-0.1.0.yml` 仅手动触发，用于生成 0.1.0 的首套签名密钥并创建 `v0.1.0` Release：

1. 在 Actions 页面运行 `Android Release 0.1.0 (one-time)`，或在仓库根目录执行 `gh workflow run "Android Release 0.1.0 (one-time)"`。
2. 工作流运行格式/分析/测试，构建 `ledger-0.1.0.apk`，创建 `v0.1.0` Release，并把签名材料放入仅保留 1 天的 artifact `android-signing-0.1.0`。
3. 在本机下载 artifact，执行 job summary 中的四条 `gh secret set`，然后删除 artifact。`v0.1.0` Release 或 tag 已存在时工作流拒绝重跑。
4. 后续版本必须复用同一密钥，Android 才能原地升级。签名密钥只放在仓库 Secrets 中，不提交到仓库。

GitHub 不允许工作流用 `GITHUB_TOKEN` 写入仓库 Secrets，因此签名材料以短期 artifact 输出，由仓库所有者落库。

2026-10-19 执行记录：run 39268947628 成功，`v0.1.0` Release 已发布（`ledger-0.1.0.apk`，56,418,150 bytes，APK V2 签名证书 SHA-256 `46881101aed6f17e5cc98e2879b8d0475d22394cba082309d7f39cc8c372c6ba`）；四个 Secrets 已落库，`android-signing-0.1.0` artifact 已删除。后续 `android.yml` 运行会检测到 keystore 并构建签名 release。

### 0.1.1 及后续 Release

`android.yml` 在推送 `v*` tag 时，复用同一次构建的 `ledger-release` artifact，校验 tag 与 `app/pubspec.yaml` 的 `version` 一致后创建 GitHub Release，附带 `ledger-<version>.apk`。发版步骤：

1. 更新 `app/pubspec.yaml` 的 `version` 与 `settings_screen.dart` 的 `APP_VERSION` 默认值。
2. 提交并推送 `master`。
3. 创建并推送对应 tag：`git tag v0.1.1 && git push origin v0.1.1`。

0.1.0 的一次性工作流保留为历史记录，后续版本不再使用。

## 约束

- 流水沿用服务端 100 条窗口，冷启动使用本地只读快照缓存；不做分页、离线写入、后台同步或推送
- 单用户、单账本；不支持反向代理子路径，服务器地址只填 origin
- 金额在客户端以分展示与校验，提交仍按后端契约发送元单位浮点
- 凭证只写入系统安全存储；服务器地址、主题与金额隐藏偏好写入普通偏好存储
- 权限声明、明文 HTTP、edge-to-edge、字体缩放与真机交互由 Android 模拟器或真机验收
