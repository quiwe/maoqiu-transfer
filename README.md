# MaoQiu Transfer

第一版目标：同一 WiFi / 同一局域网内，不经过服务器，客户端之间点对点互传文件。

核心设计：

- UDP `9526`：每 2 秒广播设备信息，超过 8 秒未出现则从附近设备列表移除。
- TCP `9527`：发送传输请求、等待接收方确认、流式传输文件数据。
- 文件接收：先写入 `.part` 临时文件，SHA-256 校验成功后再改为正式文件名。
- 保存目录：默认 `Downloads/MaoQiuTransfer`，支持在设置页修改。
- 手动 IP：发现失败时可以输入对方 IP 和端口继续发送。
- 一键快传：生成临时传输热点邀请二维码，接收端加入网络后通知发送端发起传输。
- 检查更新：启动后自动查询 GitHub Releases，并按当前平台下载 `.apk` / `.exe` / `.dmg`。

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
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
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

接收端点击“扫码接收”，可以调用相机扫描二维码。Android 端会通过系统 Wi-Fi 连接请求尝试加入二维码中的热点；系统可能弹出确认窗口。加入后接收端通知发送端，发送端校验 token 成功后，使用现有 TCP 传输协议向接收端发起传输请求，接收端仍需手动确认。

当前仓库已经实现 Dart 侧邀请、token 校验、二维码显示、相机扫码、系统 Wi-Fi 加入请求和热点加入握手。Android `LocalOnlyHotspot` 通过平台通道接入：

```text
MethodChannel: maoqiu_transfer/hotspot
startLocalOnlyHotspot({ suggestedSsid, suggestedPassword })
  -> { ssid, password, hostIp }
stopLocalOnlyHotspot()
connectToWifi({ ssid, password })
releaseWifiNetwork()
```

Android 会使用系统 `LocalOnlyHotspot` 创建本地热点，并把系统返回的真实热点名称和密码写入二维码。

## 检查更新

客户端当前版本定义在 `lib/services/app_info.dart` 和 `pubspec.yaml`。启动后会自动请求：

```text
https://api.github.com/repos/quiwe/maoqiu-transfer/releases/latest
```

如果最新 Release 版本号高于当前版本，客户端会按平台选择对应资产：

```text
Android: .apk
Windows: *windows*.exe
macOS: *macos*.dmg / *mac*.dmg
Linux: *linux*.AppImage / .deb / .tar.gz / .zip
```

设置页会显示当前版本、最新版本、安装包名称和下载进度。下载文件保存到：

```text
Downloads/MaoQiuTransfer/Updates
```

如果 GitHub 仓库保持私有，客户端无法无凭据访问 Release API；需要公开 Release，或后续改成自建更新清单接口。

## 在线 APK 打包

推送到 `main` 后，GitHub Actions 会运行 `.github/workflows/android-apk.yml`：

```text
flutter create . --platforms=android
./tool/patch_android_platform.sh
flutter pub get
flutter analyze
flutter build apk --release
```

构建成功后，APK 会作为 artifact 上传，名称为 `maoqiu-transfer-v0.2.0-android-apk`。

## 第一版验收

1. 两台设备连接同一个 WiFi。
2. 两台设备都打开客户端后，可以互相发现。
3. 发送端选择目标设备和文件。
4. 接收端弹出确认窗口。
5. 接收后双方显示进度。
6. 完成后文件保存在保存目录中，并通过 SHA-256 校验。
7. 同名文件自动改名，不覆盖旧文件。
8. 关闭重开后设备 ID 保持不变。
