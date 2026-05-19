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

if ! grep -q "android.permission.CAMERA" "$manifest"; then
  perl -0pi -e 's#<manifest([^>]*)>#<manifest$1>\n    <uses-permission android:name="android.permission.CAMERA" />\n    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />#' "$manifest"
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
import android.net.wifi.WifiNetworkSpecifier
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.NetworkInterface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private val channelName = "maoqiu_transfer/hotspot"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "startLocalOnlyHotspot" -> startLocalOnlyHotspot(call, result)
                    "stopLocalOnlyHotspot" -> {
                        stopLocalOnlyHotspot()
                        result.success(null)
                    }
                    "connectToWifi" -> connectToWifi(call, result)
                    "releaseWifiNetwork" -> {
                        releaseWifiNetwork()
                        result.success(null)
                    }
                    "acquireMulticastLock" -> acquireMulticastLock(result)
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        releaseWifiNetwork()
        releaseMulticastLock()
        stopLocalOnlyHotspot()
        super.onDestroy()
    }

    private fun acquireMulticastLock(result: MethodChannel.Result) {
        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        val current = multicastLock
        if (current?.isHeld == true) {
            result.success(null)
            return
        }

        multicastLock = wifiManager.createMulticastLock("maoqiu_transfer_discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
        result.success(null)
    }

    private fun releaseMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {
        }
        multicastLock = null
    }

    private fun startLocalOnlyHotspot(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported_android_version", "LocalOnlyHotspot requires Android 8.0 or newer.", null)
            return
        }

        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        hotspotReservation?.close()
        hotspotReservation = null

        val callback = object : WifiManager.LocalOnlyHotspotCallback() {
            override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                hotspotReservation = reservation
                val credentials = hotspotCredentials(reservation)
                result.success(
                    mapOf(
                        "ssid" to credentials.first,
                        "password" to credentials.second,
                        "hostIp" to findHotspotHostIp(wifiManager)
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
        }

        @Suppress("DEPRECATION")
        wifiManager.startLocalOnlyHotspot(callback, mainHandler)
    }

    private fun stopLocalOnlyHotspot() {
        hotspotReservation?.close()
        hotspotReservation = null
    }

    private fun connectToWifi(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported_android_version", "Automatic Wi-Fi join requires Android 10 or newer.", null)
            return
        }

        val ssid = call.argument<String>("ssid") ?: ""
        val password = call.argument<String>("password") ?: ""
        if (ssid.isBlank()) {
            result.error("invalid_ssid", "SSID is empty.", null)
            return
        }

        val connectivityManager = applicationContext.getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        releaseWifiNetwork()

        val specifierBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotBlank()) {
            specifierBuilder.setWpa2Passphrase(password)
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifierBuilder.build())
            .build()

        val completed = AtomicBoolean(false)
        val timeout = Runnable {
            if (completed.compareAndSet(false, true)) {
                releaseWifiNetwork()
                result.error("wifi_connection_timeout", "Timed out waiting for Wi-Fi connection.", null)
            }
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (completed.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    wifiNetworkCallback = this
                    connectivityManager.bindProcessToNetwork(network)
                    result.success(true)
                }
            }

            override fun onUnavailable() {
                if (completed.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    releaseWifiNetwork()
                    result.error("wifi_unavailable", "The requested Wi-Fi network was unavailable or rejected.", null)
                }
            }

            override fun onLost(network: Network) {
                releaseWifiNetwork()
            }
        }

        wifiNetworkCallback = callback
        connectivityManager.requestNetwork(request, callback)
        mainHandler.postDelayed(timeout, 60000)
    }

    private fun releaseWifiNetwork() {
        val connectivityManager = applicationContext.getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        wifiNetworkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        wifiNetworkCallback = null
        connectivityManager.bindProcessToNetwork(null)
    }

    private fun hotspotCredentials(reservation: WifiManager.LocalOnlyHotspotReservation): Pair<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val softApConfig = reservation.softApConfiguration
            val ssid = softApConfig.ssid ?: ""
            val password = softApConfig.passphrase ?: ""
            if (ssid.isNotBlank()) {
                return Pair(ssid, password)
            }
        }

        @Suppress("DEPRECATION")
        val configuration = reservation.wifiConfiguration
        return Pair(
            configuration?.SSID?.trim('"') ?: "",
            configuration?.preSharedKey?.trim('"') ?: ""
        )
    }

    private fun findHotspotHostIp(wifiManager: WifiManager): String {
        @Suppress("DEPRECATION")
        val gateway = wifiManager.dhcpInfo?.gateway ?: 0
        if (gateway != 0) {
            return intToIpv4(gateway)
        }
        return findLocalIpv4()
    }

    private fun intToIpv4(value: Int): String {
        val bytes = ByteBuffer.allocate(4)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putInt(value)
            .array()
        return InetAddress.getByAddress(bytes).hostAddress ?: "192.168.43.1"
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
