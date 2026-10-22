package com.example.road_companion

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ConcurrentHashMap

/**
 * Servicio del sistema Android para observar notificaciones de navegación vehicular.
 *
 * PRIVACIDAD Y SEGURIDAD:
 * - Filtra de forma estricta únicamente los paquetes oficiales de Google Maps y Waze.
 * - No almacena de forma persistente los textos de las notificaciones.
 * - No transmite datos a servidores externos ni registra información sensible en logs.
 * - Deduplica eventos consecutivos repetidos para proteger el rendimiento de la CPU.
 */
class NavigationNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PACKAGE_GOOGLE_MAPS = "com.google.android.apps.maps"
        const val PACKAGE_WAZE = "com.waze"

        private val ALLOWED_PACKAGES = setOf(PACKAGE_GOOGLE_MAPS, PACKAGE_WAZE)

        // Callback hacia el receptor activo en Flutter
        var notificationListener: ((Map<String, Any?>) -> Unit)? = null

        // Registro en memoria del último hash recibido por paquete para evitar ráfagas duplicadas
        private val lastPayloadHashByPackage = ConcurrentHashMap<String, Int>()

        /**
         * Verifica si el usuario ha habilitado el permiso de acceso a notificaciones para esta app.
         */
        fun isNotificationAccessGranted(context: Context): Boolean {
            val packageName = context.packageName
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            if (flat != null && flat.contains(packageName)) {
                return true
            }
            val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(context)
            return enabledPackages.contains(packageName)
        }

        /**
         * Crea el Intent del sistema para abrir la pantalla de ajustes de acceso a notificaciones.
         */
        fun createSettingsIntent(context: Context): Intent {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).apply {
                    putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        ComponentName(context, NavigationNotificationListenerService::class.java).flattenToString()
                    )
                }
            } else {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            }
        }

        /**
         * Limpia la memoria de deduplicación.
         */
        fun clearCache() {
            lastPayloadHashByPackage.clear()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        // 1. Filtrado riguroso de paquetes
        if (!ALLOWED_PACKAGES.contains(packageName)) {
            return
        }

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        // 2. Extracción segura de campos de texto disponibles
        val title = extras.getCharSequence("android.title")?.toString()
            ?: extras.getCharSequence("android.title.big")?.toString()
        val text = extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString()
        val subText = extras.getCharSequence("android.subText")?.toString()

        // Si todos los campos de texto están vacíos, no es una indicación útil
        if (title.isNullOrBlank() && text.isNullOrBlank() && subText.isNullOrBlank()) {
            return
        }

        // 3. Deduplicación de eventos consecutivos idénticos
        val payloadHash = (packageName + "|" + (title ?: "") + "|" + (text ?: "") + "|" + (subText ?: "")).hashCode()
        val previousHash = lastPayloadHashByPackage[packageName]
        if (previousHash == payloadHash) {
            // El contenido no cambió con respecto al último evento recibido de este paquete
            return
        }
        lastPayloadHashByPackage[packageName] = payloadHash

        // 4. Estructuración del evento
        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["title"] = title
        payload["text"] = text
        payload["subText"] = subText
        payload["timestamp"] = sbn.postTime
        payload["isRemoved"] = false

        // 5. Envío al listener de Flutter en el hilo correspondiente
        notificationListener?.invoke(payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        if (!ALLOWED_PACKAGES.contains(packageName)) {
            return
        }

        lastPayloadHashByPackage.remove(packageName)

        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["title"] = null
        payload["text"] = null
        payload["subText"] = null
        payload["timestamp"] = System.currentTimeMillis()
        payload["isRemoved"] = true

        notificationListener?.invoke(payload)
    }
}
