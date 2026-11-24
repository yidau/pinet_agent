package net.piagent.piagent

import android.Manifest
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var notificationResult: MethodChannel.Result? = null
    private val enrollment by lazy { EnrollmentChannel(this) }

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(MonitoringService.engineId)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(MonitoringService.engineId, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.piagent.piagent/time_sync")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestBluetoothPermissions") {
                    requestBluetoothPermissions(result)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.piagent.piagent/enrollment")
            .setMethodCallHandler(enrollment::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MonitoringService.channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (notificationResult != null) {
                                result.success(false)
                            } else {
                                notificationResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionsRequest)
                            }
                        } else {
                            startMonitoring(result)
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, MonitoringService::class.java))
                        result.success(false)
                    }
                    "notifyRisk" -> {
                        val id = call.argument<String>("id").orEmpty()
                        val message = call.argument<String>("message").orEmpty()
                        MonitoringService.notifyRisk(applicationContext, id, message)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startMonitoring(result: MethodChannel.Result) {
        if (MonitoringService.running) {
            result.success(true)
            return
        }
        if (MonitoringService.startResult != null) {
            result.success(false)
            return
        }
        val app = applicationContext
        MonitoringService.startResult = { enabled -> result.success(enabled) }
        try {
            val intent = Intent(app, MonitoringService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent)
            else app.startService(intent)
        } catch (_: RuntimeException) {
            MonitoringService.completeStart(false)
        }
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("permission_request_in_progress", "等待蓝牙权限请求完成。", null)
            return
        }
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            // Android 12 and later do not use location permissions for this BLE scan.
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(permissions, bluetoothPermissionsRequest)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == bluetoothPermissionsRequest) {
            permissionResult?.success(
                grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED },
            )
            permissionResult = null
        }
        if (requestCode == notificationPermissionsRequest) {
            val result = notificationResult
            notificationResult = null
            if (result != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startMonitoring(result)
                else result.success(false)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        enrollment.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val bluetoothPermissionsRequest = 2041
        private const val notificationPermissionsRequest = 2042
    }
}
