package net.piagent.piagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MonitoringService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == stopAction) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = notificationManager(this)
            createChannels(manager)
            if (!manager.areNotificationsEnabled() ||
                FlutterEngineCache.getInstance().get(engineId) == null ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    manager.getNotificationChannel(statusChannel)?.importance == NotificationManager.IMPORTANCE_NONE)) {
                throw IllegalStateException("Notification channel unavailable")
            }
            val stop = PendingIntent.getService(this, 1, Intent(this, MonitoringService::class.java).setAction(stopAction),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification = builder(this, statusChannel)
                .setContentTitle("PocketNet 持续告警接收")
                .setContentText("连接设备热点时接收告警")
                .setOngoing(true)
                .addAction(Notification.Action.Builder(null, "停止", stop).build())
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(statusId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(statusId, notification)
            }
            running = true
            completeStart(true)
        } catch (_: RuntimeException) {
            completeStart(false)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        completeStart(false)
        val engine = FlutterEngineCache.getInstance().get(engineId)
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, channelName).invokeMethod("stopped", null)
        }
        super.onDestroy()
    }

    companion object {
        const val engineId = "pocketnet.monitoring"
        const val channelName = "net.piagent.piagent/monitoring"
        private const val statusChannel = "monitoring_status"
        private const val alertChannel = "security_alerts"
        private const val stopAction = "net.piagent.piagent.STOP_MONITORING"
        private const val statusId = 2400
        var running = false
            private set
        var startResult: ((Boolean) -> Unit)? = null

        fun completeStart(enabled: Boolean) {
            val callback = startResult
            startResult = null
            callback?.invoke(enabled)
        }

        private fun notificationManager(context: Context) =
            context.getSystemService(NotificationManager::class.java)

        private fun createChannels(manager: NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(
                    statusChannel, "持续接收状态", NotificationManager.IMPORTANCE_LOW))
                manager.createNotificationChannel(NotificationChannel(
                    alertChannel, "无线安全告警", NotificationManager.IMPORTANCE_HIGH))
            }
        }

        @Suppress("DEPRECATION")
        private fun builder(context: Context, channel: String): Notification.Builder {
            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channel)
            } else {
                Notification.Builder(context)
            }
            val launch = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            return notification.setSmallIcon(android.R.drawable.stat_sys_warning).setContentIntent(launch)
        }

        fun notifyRisk(context: Context, id: String, message: String) {
            if (!running || !id.matches(Regex("[a-f0-9]{32}"))) return
            val manager = notificationManager(context)
            if (!manager.areNotificationsEnabled()) return
            val notification = builder(context, alertChannel)
                .setContentTitle("PocketNet 无线安全告警")
                .setContentText(message.take(120))
                .setAutoCancel(true)
                .build()
            manager.notify(id, 2401, notification)
        }
    }
}
