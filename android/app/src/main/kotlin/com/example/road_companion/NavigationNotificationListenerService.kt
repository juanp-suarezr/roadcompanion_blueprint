package com.example.road_companion

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
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

        // Paquete de navegación seleccionado por el usuario para el viaje actual.
        // null o "all" acepta ambos; "none" desactiva la captura externa;
        // "com.waze" o "com.google.android.apps.maps" filtra exclusivamente esa app.
        @Volatile
        var selectedSourcePackage: String? = null

        @Volatile
        var isListenerConnected: Boolean = false
            private set

        // Callback hacia el receptor activo en Flutter
        var notificationListener: ((Map<String, Any?>) -> Unit)? = null

        // Registro en memoria del último hash recibido por paquete para evitar ráfagas duplicadas
        private val lastPayloadHashByPackage = ConcurrentHashMap<String, Int>()
        private val lastPostTimeByPackage = ConcurrentHashMap<String, Long>()
        private val activeNavNotificationIdByPackage = ConcurrentHashMap<String, Int>()

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
            lastPostTimeByPackage.clear()
            activeNavNotificationIdByPackage.clear()
        }

        private fun isPackageAllowedForCurrentSelection(packageName: String): Boolean {
            if (!ALLOWED_PACKAGES.contains(packageName)) return false
            val target = selectedSourcePackage
            if (target == null || target == "all" || target.isEmpty()) return true
            if (target == "none") return false
            return target == packageName
        }

        private fun isGenericRunningBanner(text: String?): Boolean {
            if (text.isNullOrBlank()) return false
            val lower = text.lowercase()
            return lower.contains("en ejecución") ||
                lower.contains("en ejecucion") ||
                lower.contains("toca para abrir") ||
                lower.contains("toque para abrir") ||
                lower.contains("tap to open") ||
                lower.contains("touch to open") ||
                lower.contains("running.") ||
                lower.contains("running in background") ||
                lower == "running"
        }

        private val IRRELEVANT_ACTION_LABELS = setOf(
            "waze",
            "google maps",
            "maps",
            "cerrar",
            "salir",
            "detener",
            "cancelar",
            "apagar",
            "silenciar",
            "stop",
            "exit",
            "dismiss",
            "close",
            "mute"
        )

        private fun isIrrelevantRemoteViewLabel(text: String?): Boolean {
            if (text.isNullOrBlank()) return true
            val normalized = text.trim().lowercase()
            if (IRRELEVANT_ACTION_LABELS.contains(normalized)) return true
            return isGenericRunningBanner(normalized)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isListenerConnected = true
    }

    override fun onListenerDisconnected() {
        isListenerConnected = false
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        // 1. Filtrado riguroso de paquetes según la fuente seleccionada para el viaje
        if (!isPackageAllowedForCurrentSelection(packageName)) {
            return
        }

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle.EMPTY

        // 2. Descartar eventos fuera de orden temporal para el mismo paquete
        val postTime = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()
        val lastPostTime = lastPostTimeByPackage[packageName]
        if (lastPostTime != null && postTime + 2000L < lastPostTime) {
            return
        }

        // 3. Extracción exhaustiva de campos de texto (extras estándar, textLines, ticker y RemoteViews)
        val rawTitleOrig = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()
        var title = rawTitleOrig
        val rawText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        val summaryText = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
        val infoText = extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()
        val tickerText = notification.tickerText?.toString()

        val textLinesArray = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
        val joinedLines = textLinesArray
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.joinToString(" — ")

        // Inventario seguro de claves presentes (sin datos personales) para diagnóstico estructurado
        val presentExtras = mutableListOf<String>()
        if (!rawTitleOrig.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TITLE)
        if (!rawText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TEXT)
        if (!bigText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_BIG_TEXT)
        if (!subText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_SUB_TEXT)
        if (!summaryText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_SUMMARY_TEXT)
        if (!infoText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_INFO_TEXT)
        if (!joinedLines.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TEXT_LINES)
        if (!tickerText.isNullOrBlank()) presentExtras.add("tickerText")
        @Suppress("DEPRECATION")
        if (notification.contentView != null) presentExtras.add("contentView")
        @Suppress("DEPRECATION")
        if (notification.bigContentView != null) presentExtras.add("bigContentView")
        @Suppress("DEPRECATION")
        if (notification.headsUpContentView != null) presentExtras.add("headsUpContentView")

        // Extraer textos visibles de RemoteViews personalizados (usados por Waze y Google Maps en Android)
        val remoteViewTexts = extractTextsFromRemoteViews(notification)

        var text = when {
            !bigText.isNullOrBlank() && !isGenericRunningBanner(bigText) -> bigText
            !rawText.isNullOrBlank() && !isGenericRunningBanner(rawText) -> rawText
            !joinedLines.isNullOrBlank() -> joinedLines
            remoteViewTexts.isNotEmpty() -> remoteViewTexts.joinToString(" — ")
            !rawText.isNullOrBlank() -> rawText
            else -> bigText
        }

        // Si el título es solo el nombre de la app ("Waze" / "Google Maps") y RemoteViews o ticker
        // contiene fragmentos adicionales (ej. distancia en primer TextView y giro en el segundo), enriquecer:
        if (remoteViewTexts.isNotEmpty()) {
            val nonTrivialRemote = remoteViewTexts.filter { !isIrrelevantRemoteViewLabel(it) }
            if (nonTrivialRemote.isNotEmpty()) {
                if (title.isNullOrBlank() || isIrrelevantRemoteViewLabel(title)) {
                    title = nonTrivialRemote.first()
                }
                if (text.isNullOrBlank() || isGenericRunningBanner(text)) {
                    text = if (nonTrivialRemote.size > 1) {
                        nonTrivialRemote.drop(1).joinToString(" — ")
                    } else {
                        nonTrivialRemote.first()
                    }
                }
            }
        }

        if ((text.isNullOrBlank() || isGenericRunningBanner(text)) &&
            !tickerText.isNullOrBlank() &&
            !isGenericRunningBanner(tickerText)
        ) {
            text = tickerText
        }

        val effectiveSubText = listOfNotNull(subText, summaryText, infoText)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }

        // Si todos los campos de texto están vacíos, no es una indicación útil
        if (title.isNullOrBlank() && text.isNullOrBlank() && effectiveSubText.isNullOrBlank()) {
            return
        }

        val combinedCheck = "${title ?: ""} ${text ?: ""}"
        if (!isGenericRunningBanner(combinedCheck)) {
            activeNavNotificationIdByPackage[packageName] = sbn.id
        }

        // 4. Deduplicación de eventos consecutivos idénticos
        val payloadHash = (packageName + "|" + (title ?: "") + "|" + (text ?: "") + "|" + (effectiveSubText ?: "")).hashCode()
        val previousHash = lastPayloadHashByPackage[packageName]
        if (previousHash == payloadHash) {
            return
        }
        lastPayloadHashByPackage[packageName] = payloadHash
        lastPostTimeByPackage[packageName] = postTime

        // 5. Estructuración del evento
        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["title"] = title
        payload["text"] = text
        payload["subText"] = effectiveSubText
        payload["bigText"] = bigText ?: joinedLines
        payload["availableExtras"] = presentExtras
        payload["remoteViewsTexts"] = remoteViewTexts
        payload["timestamp"] = postTime
        payload["isRemoved"] = false

        // 6. Envío al listener de Flutter en el hilo correspondiente
        notificationListener?.invoke(payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        if (!isPackageAllowedForCurrentSelection(packageName)) {
            return
        }

        val trackedId = activeNavNotificationIdByPackage[packageName]
        if (trackedId != null && trackedId != sbn.id) {
            // Se cerró una notificación secundaria pero la notificación de navegación principal sigue activa
            return
        }

        val removalTime = System.currentTimeMillis()
        activeNavNotificationIdByPackage.remove(packageName)
        lastPayloadHashByPackage.remove(packageName)
        // Conservar marca de tiempo de eliminación para impedir que una notificación tardía
        // con postTime anterior reactive una maniobra ya cancelada.
        lastPostTimeByPackage[packageName] = removalTime

        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["title"] = null
        payload["text"] = null
        payload["subText"] = null
        payload["timestamp"] = removalTime
        payload["isRemoved"] = true

        notificationListener?.invoke(payload)
    }

    private fun extractTextsFromRemoteViews(notification: Notification): List<String> {
        val result = mutableListOf<String>()
        try {
            @Suppress("DEPRECATION")
            val candidates = listOfNotNull(
                notification.bigContentView,
                notification.contentView,
                notification.headsUpContentView
            )
            for (rv in candidates) {
                val container = FrameLayout(applicationContext)
                val inflated: View = rv.apply(applicationContext, container)
                collectTextViews(inflated, result)
                if (result.isNotEmpty()) break
            }
        } catch (_: Throwable) {
            // Si algún RemoteViews de terceros requiere permisos o recursos privados, ignorar de forma segura
        }
        return result.distinct()
    }

    private fun collectTextViews(view: View?, out: MutableList<String>) {
        if (view == null) return
        if (view is TextView) {
            val value = view.text?.toString()?.trim()
            if (!value.isNullOrEmpty()) {
                out.add(value)
            }
        } else if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                collectTextViews(view.getChildAt(i), out)
            }
        }
    }
}
