#!/usr/bin/env bash
set -euo pipefail

manifest="android/app/src/main/AndroidManifest.xml"
activity="$(find android/app/src/main/kotlin -name MainActivity.kt 2>/dev/null | head -n 1)"

if [[ ! -f "$manifest" ]]; then
  echo "AndroidManifest.xml not found. Run flutter create . --platforms=android first." >&2
  exit 1
fi

if [[ -z "${activity:-}" || ! -f "$activity" ]]; then
  echo "MainActivity not found. Run flutter create . --platforms=android first." >&2
  exit 1
fi

if ! grep -q "CHANGE_WIFI_MULTICAST_STATE" "$manifest"; then
  perl -0pi -e 's#<manifest([^>]*)>#<manifest$1>\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />\n    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />\n    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />#' "$manifest"
fi

perl -0pi -e 's/android:label="[^"]*"/android:label="毛球互传"/' "$manifest"

for gradle_file in android/app/build.gradle android/app/build.gradle.kts; do
  if [[ -f "$gradle_file" ]]; then
    perl -0pi -e 's/compileSdk\s*=\s*flutter\.compileSdkVersion/compileSdk = 36/g; s/compileSdkVersion\s+flutter\.compileSdkVersion/compileSdkVersion 36/g; s/targetSdk\s*=\s*flutter\.targetSdkVersion/targetSdk = 35/g; s/targetSdkVersion\s+flutter\.targetSdkVersion/targetSdkVersion 35/g' "$gradle_file"
  fi
done

package_line="$(grep -E '^package ' "$activity" | head -n 1 || true)"
if [[ -z "$package_line" ]]; then
  package_line="package com.example.maoqiu_transfer"
fi

cat > "$activity" <<KOTLIN
$package_line

import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private val channelName = "maoqiu_transfer/hotspot"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "startLocalOnlyHotspot" -> startLocalOnlyHotspot(result)
                    "stopLocalOnlyHotspot" -> {
                        stopLocalOnlyHotspot()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        stopLocalOnlyHotspot()
        super.onDestroy()
    }

    private fun startLocalOnlyHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported_android_version", "LocalOnlyHotspot requires Android 8.0 or newer.", null)
            return
        }

        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        hotspotReservation?.close()
        hotspotReservation = null

        wifiManager.startLocalOnlyHotspot(
            object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspotReservation = reservation
                    val configuration = reservation.wifiConfiguration
                    result.success(
                        mapOf(
                            "ssid" to (configuration?.SSID?.trim('"') ?: ""),
                            "password" to (configuration?.preSharedKey?.trim('"') ?: ""),
                            "hostIp" to findLocalIpv4()
                        )
                    )
                }

                override fun onStopped() {
                    hotspotReservation = null
                }

                override fun onFailed(reason: Int) {
                    hotspotReservation = null
                    result.error("local_only_hotspot_failed", "LocalOnlyHotspot failed with reason: \$reason", reason)
                }
            },
            Handler(Looper.getMainLooper())
        )
    }

    private fun stopLocalOnlyHotspot() {
        hotspotReservation?.close()
        hotspotReservation = null
    }

    private fun findLocalIpv4(): String {
        return try {
            NetworkInterface.getNetworkInterfaces().toList()
                .flatMap { it.inetAddresses.toList() }
                .firstOrNull {
                    !it.isLoopbackAddress &&
                        it.hostAddress?.contains(":") == false &&
                        it.hostAddress?.startsWith("169.254.") == false
                }?.hostAddress ?: "192.168.43.1"
        } catch (_: Exception) {
            "192.168.43.1"
        }
    }
}
KOTLIN

echo "Android platform files patched for MaoQiu Transfer APK."
