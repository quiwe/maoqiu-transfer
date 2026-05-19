# MaoQiu Transfer

第一版目标：同一 WiFi / 同一局域网内，不经过服务器，客户端之间点对点互传文件。

核心设计：

- UDP `9526`：每 2 秒广播设备信息，超过 8 秒未出现则从附近设备列表移除。
- TCP `9527`：发送传输请求、等待接收方确认、流式传输文件数据。
- 文件接收：先写入 `.part` 临时文件，SHA-256 校验成功后再改为正式文件名。
- 保存目录：默认 `Downloads/MaoQiuTransfer`，支持在设置页修改。
- 手动 IP：发现失败时可以输入对方 IP 和端口继续发送。
- 一键快传：生成临时传输热点邀请二维码，接收端加入网络后通知发送端发起传输。

## 当前仓库状态

这个目录已经包含 Flutter 源码、服务层和 UI。由于本机当前没有安装 `flutter` / `dart` 命令，平台目录需要在安装 Flutter 后生成：

```sh
flutter create . --platforms=android
./tool/patch_android_platform.sh
flutter pub get
flutter run -d android
```

Android 端生成平台目录后，需要确认 `android/app/src/main/AndroidManifest.xml` 至少包含：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
```

仓库里的 `tool/patch_android_platform.sh` 会在生成 Android 平台目录后自动补齐这些权限、APK 应用名和 `LocalOnlyHotspot` 原生通道。GitHub Actions 在线打包也会执行这个脚本。

## 连接模式

### 同一 WiFi 自动发现

两台设备都打开客户端后，通过 UDP 广播自动出现在首页“附近设备”列表中。点击设备后选择文件发送。

### 手动 IP

当 UDP 广播被路由器或系统防火墙拦截时，可以点击“手动 IP”，输入对方客户端显示的 IP 和端口，继续走 TCP 文件传输。

### 一键快传 / 热点二维码

发送端点击“一键快传”，选择文件后生成 5 分钟有效的邀请二维码：

```json
{
  "mode": "hotspot",
  "ssid": "MaoQiu-Transfer-A8F2",
  "password": "mq-8392-1947",
  "hostIp": "192.168.43.1",
  "port": 9527,
  "token": "temporary-token",
  "expireAt": "datetime"
}
```

接收端点击“扫码接收”，加入二维码中的 WiFi 后通知发送端。发送端校验 token 成功后，使用现有 TCP 传输协议向接收端发起传输请求，接收端仍需手动确认。当前源码先支持粘贴二维码 JSON 内容，摄像头扫码可以在平台目录生成后接入 `mobile_scanner` 或系统扫码能力。

当前仓库已经实现 Dart 侧邀请、token 校验、二维码显示和热点加入握手。Android `LocalOnlyHotspot` 通过平台通道接入：

```text
MethodChannel: maoqiu_transfer/hotspot
startLocalOnlyHotspot({ suggestedSsid, suggestedPassword })
  -> { ssid, password, hostIp }
stopLocalOnlyHotspot()
```

在原生通道接入前，一键快传会退化为“生成邀请二维码 + 用户手动加入对应 WiFi / 同一网络后继续”。

## 在线 APK 打包

推送到 `main` 后，GitHub Actions 会运行 `.github/workflows/android-apk.yml`：

```text
flutter create . --platforms=android
./tool/patch_android_platform.sh
flutter pub get
flutter analyze
flutter build apk --release
```

构建成功后，APK 会作为 artifact 上传，名称为 `maoqiu-transfer-release-apk`。

## 第一版验收

1. 两台设备连接同一个 WiFi。
2. 两台设备都打开客户端后，可以互相发现。
3. 发送端选择目标设备和文件。
4. 接收端弹出确认窗口。
5. 接收后双方显示进度。
6. 完成后文件保存在保存目录中，并通过 SHA-256 校验。
7. 同名文件自动改名，不覆盖旧文件。
8. 关闭重开后设备 ID 保持不变。
