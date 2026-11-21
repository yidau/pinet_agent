package net.piagent.piagent

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.piagent.piagent/time_sync")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestBluetoothPermissions") {
                    requestBluetoothPermissions(result)
                } else {
                    result.notImplemented()
                }
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
    }

    companion object {
        private const val bluetoothPermissionsRequest = 2041
    }
}
