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

仓库根目录的 `make app-analyze`、`make app-test`、`make app-web` 分别封装前三项检查与 Web 构建。

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

## 约束

- 流水沿用服务端 100 条窗口，不做分页、离线库、后台同步或推送
- 单用户、单账本；不支持反向代理子路径，服务器地址只填 origin
- 金额在客户端以分展示与校验，提交仍按后端契约发送元单位浮点
- 凭证只写入系统安全存储；服务器地址、主题与金额隐藏偏好写入普通偏好存储
- 权限声明、明文 HTTP、edge-to-edge、字体缩放与真机交互由 Android 模拟器或真机验收
