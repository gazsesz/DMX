package com.gazsesz.dmx_controller

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var connectivityManager: ConnectivityManager? = null
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null

    /**
     * Lets Dart start and stop [RemoteControlService], and check whether
     * Android is still allowed to doze the app.
     *
     * Dart can bind an HTTP socket perfectly well on its own — what it
     * cannot do is stop Android freezing the process once the screen goes
     * off, which is exactly when a remote trigger needs to land.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bindProcessToActiveWifi()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    // From Android 13 the service still runs without this,
                    // but its notification is suppressed — so the endpoint
                    // would be listening with nothing on screen to say so.
                    ensureNotificationPermission()
                    RemoteControlService.start(this)
                    result.success(true)
                }
                "stop" -> {
                    RemoteControlService.stop(this)
                    result.success(true)
                }
                "isBatteryOptimized" -> result.success(isBatteryOptimized())
                // Opens the system dialog. Android only allows the app to
                // ask; the user is the one who decides, so the caller has
                // to re-check rather than assume this worked.
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Art-Net/sACN only reach the node over whatever Wi-Fi it's actually on
     * — often an isolated AP (e.g. an EasyNode's own hotspot) with no route
     * to the internet. Android treats an unvalidated network like that as
     * lower priority than one with internet, and once the phone also has
     * mobile data up, it keeps routing *new* sockets through data instead —
     * so the app can show "connected" to the right SSID and still never
     * reach the node, until something (like toggling demo mode) happens to
     * open a fresh socket after Android has settled on the Wi-Fi. Binding
     * the whole process to the active Wi-Fi network removes that race
     * instead of relying on it to resolve itself.
     */
    private fun bindProcessToActiveWifi() {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = manager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                manager.bindProcessToNetwork(network)
            }

            override fun onLost(network: Network) {
                manager.bindProcessToNetwork(null)
            }
        }
        wifiNetworkCallback = callback
        // registerNetworkCallback, not requestNetwork: the latter asks Android to
        // *bring up* a matching network and needs CHANGE_NETWORK_STATE. This only
        // needs to hear about the Wi-Fi the user already connected in system
        // settings, which registerNetworkCallback reports for free.
        manager.registerNetworkCallback(request, callback)
    }

    override fun onDestroy() {
        wifiNetworkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        wifiNetworkCallback = null
        super.onDestroy()
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return
        // Fire and forget: the service works either way, so there is
        // nothing to do with the answer beyond letting Android record it.
        requestPermissions(arrayOf(permission), NOTIFICATION_PERMISSION_REQUEST)
    }

    private fun isBatteryOptimized(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val power = getSystemService(PowerManager::class.java) ?: return false
        return !power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
            true
        } catch (e: Exception) {
            // Some builds (and some manufacturer skins) hide this screen.
            // Falling back to the general battery settings list is better
            // than doing nothing at all.
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.gazsesz.dmx_controller/background"
        private const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }
}
