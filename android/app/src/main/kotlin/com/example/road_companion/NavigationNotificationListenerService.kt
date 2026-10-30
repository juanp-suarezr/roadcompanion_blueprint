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

        private val IGNORED_EXTRA_KEYS = setOf(
            "android.appInfo",
            "android.template",
            "android.reduced.images",
            "android.contains.customView",
            "androidx.core.app.extra.COMPAT_TEMPLATE"
        )

        // Paquete de navegación seleccionado por el usuario para el viaje actual.
        // null o "all" acepta ambos; "none" desactiva la captura externa;
        // "com.waze" o "com.google.android.apps.maps" filtra exclusivamente esa app.
        @Volatile
        var selectedSourcePackage: String? = null

        @Volatile
        var isListenerConnected: Boolean = false
            private set

        @Volatile
        private var activeInstance: NavigationNotificationListenerService? = null

        // Callback hacia el receptor activo en Flutter
        var notificationListener: ((Map<String, Any?>) -> Unit)? = null

        // Registro en memoria del último hash recibido por paquete para evitar ráfagas duplicadas
        private val lastPayloadHashByPackage = ConcurrentHashMap<String, Int>()
        private val lastPostTimeByPackage = ConcurrentHashMap<String, Long>()
        private val activeNavNotificationIdByPackage = ConcurrentHashMap<String, Int>()
        private val activeNavNotificationKeyByPackage = ConcurrentHashMap<String, String>()
        private val postedNotificationKeysByPackage = ConcurrentHashMap<String, MutableSet<String>>()

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
            activeNavNotificationKeyByPackage.clear()
            postedNotificationKeysByPackage.clear()
        }

        /**
         * Inspecciona inmediatamente las notificaciones activas en la barra de estado
         * para la fuente actualmente seleccionada (útil cuando el usuario abre o cambia a Waze/Maps
         * después de que la notificación ya fue publicada).
         */
        fun syncActiveNotificationsForCurrentSelection() {
            activeInstance?.inspectCurrentActiveNotifications()
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
                lower.contains("volver a waze") ||
                lower.contains("return to waze") ||
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
        activeInstance = this
        inspectCurrentActiveNotifications()
    }

    override fun onListenerDisconnected() {
        isListenerConnected = false
        if (activeInstance === this) {
            activeInstance = null
        }
        super.onListenerDisconnected()
    }

    fun inspectCurrentActiveNotifications() {
        try {
            val activeList = activeNotifications ?: return
            val matching = activeList.filter { sbn ->
                val pkg = sbn?.packageName
                pkg != null && isPackageAllowedForCurrentSelection(pkg)
            }
            if (matching.isEmpty()) return

            // Procesar primero notificaciones genéricas y al final las de categoría navigation
            // para que prevalezca siempre la notificación con maniobra real si hay más de una.
            val sorted = matching.sortedBy { sbn ->
                val cat = sbn.notification?.category
                if (cat == Notification.CATEGORY_NAVIGATION) 1 else 0
            }
            for (sbn in sorted) {
                processPostedNotification(sbn, isActiveSync = true)
            }
        } catch (_: Throwable) {
            // Ignorar de forma segura si el servicio aún no tiene enlace completo con el sistema
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        processPostedNotification(sbn, isActiveSync = false)
    }

    private fun processPostedNotification(sbn: StatusBarNotification?, isActiveSync: Boolean) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        // 1. Filtrado riguroso de paquetes según la fuente seleccionada para el viaje
        if (!isPackageAllowedForCurrentSelection(packageName)) {
            return
        }

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: Bundle.EMPTY
        val notificationKey = sbn.key ?: "$packageName:${sbn.id}:${sbn.tag ?: ""}"
        val notificationCategory = notification.category ?: "none"

        // Registrar que esta clave de notificación existe realmente en la sesión
        postedNotificationKeysByPackage
            .getOrPut(packageName) { ConcurrentHashMap.newKeySet() }
            .add(notificationKey)

        // 2. Descartar eventos fuera de orden temporal para el mismo paquete
        val postTime = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()
        val lastPostTime = lastPostTimeByPackage[packageName]
        if (!isActiveSync && lastPostTime != null && postTime + 2000L < lastPostTime) {
            return
        }

        // 3. Extracción exhaustiva de campos de texto (extras estándar, textLines, ticker, custom extras y RemoteViews)
        val rawTitleOrig = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString()
        var title = rawTitleOrig
        val rawText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        val summaryText = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
        val infoText = extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString()
        val shortCriticalText = extras.getCharSequence("android.shortCriticalText")?.toString()
        val tickerText = notification.tickerText?.toString()

        val textLinesArray = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
        val joinedLines = textLinesArray
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.joinToString(" — ")

        // Inventario seguro de claves presentes en Notification.extras (sin datos personales)
        val presentExtras = mutableListOf<String>()
        if (!rawTitleOrig.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TITLE)
        if (!rawText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TEXT)
        if (!bigText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_BIG_TEXT)
        if (!subText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_SUB_TEXT)
        if (!summaryText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_SUMMARY_TEXT)
        if (!infoText.isNullOrBlank()) presentExtras.add(Notification.EXTRA_INFO_TEXT)
        if (!shortCriticalText.isNullOrBlank()) presentExtras.add("android.shortCriticalText")
        if (!joinedLines.isNullOrBlank()) presentExtras.add(Notification.EXTRA_TEXT_LINES)
        if (!tickerText.isNullOrBlank()) presentExtras.add("tickerText")

        // Inspeccionar cualquier otra clave CharSequence/String presente en Notification.extras
        val customExtraTexts = mutableListOf<String>()
        val standardKeys = setOf(
            Notification.EXTRA_TITLE,
            Notification.EXTRA_TITLE_BIG,
            Notification.EXTRA_TEXT,
            Notification.EXTRA_BIG_TEXT,
            Notification.EXTRA_SUB_TEXT,
            Notification.EXTRA_SUMMARY_TEXT,
            Notification.EXTRA_INFO_TEXT,
            Notification.EXTRA_TEXT_LINES,
            "android.shortCriticalText"
        )
        try {
            for (key in extras.keySet()) {
                if (key == null || standardKeys.contains(key) || IGNORED_EXTRA_KEYS.contains(key)) {
                    continue
                }
                @Suppress("DEPRECATION")
                val rawVal = extras.get(key) ?: continue
                if (rawVal is CharSequence) {
                    val str = rawVal.toString().trim()
                    if (str.isNotEmpty() && !str.startsWith("android.app.Notification")) {
                        presentExtras.add("extra:$key")
                        if (!isIrrelevantRemoteViewLabel(str)) {
                            customExtraTexts.add(str)
                        }
                    }
                }
            }
        } catch (_: Throwable) {}

        @Suppress("DEPRECATION")
        if (notification.contentView != null) presentExtras.add("contentView")
        @Suppress("DEPRECATION")
        if (notification.bigContentView != null) presentExtras.add("bigContentView")
        @Suppress("DEPRECATION")
        if (notification.headsUpContentView != null) presentExtras.add("headsUpContentView")

        // Extraer textos visibles de RemoteViews personalizados (usando el contexto de paquete seguro)
        val remoteViewErrors = mutableListOf<String>()
        val remoteViewTexts = extractTextsFromRemoteViews(
            packageName = packageName,
            notification = notification,
            errorsOut = remoteViewErrors
        )
        for (err in remoteViewErrors) {
            presentExtras.add("remoteViewsError:$err")
        }

        var text = when {
            !bigText.isNullOrBlank() && !isGenericRunningBanner(bigText) -> bigText
            !rawText.isNullOrBlank() && !isGenericRunningBanner(rawText) -> rawText
            !shortCriticalText.isNullOrBlank() && !isGenericRunningBanner(shortCriticalText) -> shortCriticalText
            !joinedLines.isNullOrBlank() -> joinedLines
            remoteViewTexts.isNotEmpty() -> remoteViewTexts.joinToString(" — ")
            customExtraTexts.isNotEmpty() -> customExtraTexts.joinToString(" — ")
            !rawText.isNullOrBlank() -> rawText
            else -> bigText
        }

        // Si el título es solo el nombre de la app ("Waze" / "Google Maps") y RemoteViews o customExtras
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

        val effectiveSubText = listOfNotNull(subText, summaryText, infoText, shortCriticalText)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() && it != text && it != title }

        val isEmptyText = title.isNullOrBlank() && text.isNullOrBlank() && effectiveSubText.isNullOrBlank()

        val combinedCheck = "${title ?: ""} ${text ?: ""}"
        if (!isEmptyText && !isGenericRunningBanner(combinedCheck)) {
            activeNavNotificationIdByPackage[packageName] = sbn.id
            activeNavNotificationKeyByPackage[packageName] = notificationKey
        }

        // 4. Deduplicación de eventos consecutivos idénticos
        val payloadHash = (
            packageName + "|" +
                notificationKey + "|" +
                (title ?: "") + "|" +
                (text ?: "") + "|" +
                (effectiveSubText ?: "") + "|" +
                remoteViewTexts.joinToString(",")
            ).hashCode()
        val previousHash = lastPayloadHashByPackage[packageName]
        if (!isActiveSync && previousHash == payloadHash) {
            return
        }
        lastPayloadHashByPackage[packageName] = payloadHash
        lastPostTimeByPackage[packageName] = postTime

        // 5. Estructuración del evento (incluyendo notificaciones vacías para diagnóstico explícito)
        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["notificationId"] = sbn.id
        payload["notificationKey"] = notificationKey
        payload["notificationCategory"] = notificationCategory
        payload["isOngoing"] = sbn.isOngoing
        payload["isEmptyText"] = isEmptyText
        payload["title"] = title
        payload["text"] = text
        payload["subText"] = effectiveSubText
        payload["bigText"] = bigText ?: joinedLines
        payload["availableExtras"] = presentExtras
        payload["remoteViewsTexts"] = remoteViewTexts
        payload["timestamp"] = postTime
        payload["isRemoved"] = false

        // 6. Envío al listener de Flutter
        notificationListener?.invoke(payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return

        if (!isPackageAllowedForCurrentSelection(packageName)) {
            return
        }

        val notificationKey = sbn.key ?: "$packageName:${sbn.id}:${sbn.tag ?: ""}"
        val seenKeys = postedNotificationKeysByPackage[packageName]
        val trackedKey = activeNavNotificationKeyByPackage[packageName]
        val trackedId = activeNavNotificationIdByPackage[packageName]

        // Si había una notificación principal de navegación activa y la que se cerró es otra secundaria, ignorar
        if (trackedKey != null && trackedKey != notificationKey) {
            seenKeys?.remove(notificationKey)
            return
        }
        if (trackedId != null && trackedId != sbn.id) {
            seenKeys?.remove(notificationKey)
            return
        }

        // Si la notificación que se elimina nunca fue recibida en esta sesión de diagnóstico,
        // no emitir un falso evento STALE vacío; verificar en su lugar si queda otra notificación activa.
        if (seenKeys == null || !seenKeys.remove(notificationKey)) {
            inspectCurrentActiveNotifications()
            return
        }

        // Si el paquete todavía mantiene otra notificación activa en la barra de estado,
        // sincronizar esa notificación en vez de declarar la navegación como finalizada/STALE.
        try {
            val remainingActive = activeNotifications?.filter {
                it?.packageName == packageName && it.key != sbn.key
            }
            if (!remainingActive.isNullOrEmpty()) {
                activeNavNotificationIdByPackage.remove(packageName)
                activeNavNotificationKeyByPackage.remove(packageName)
                lastPayloadHashByPackage.remove(packageName)
                for (rem in remainingActive) {
                    processPostedNotification(rem, isActiveSync = true)
                }
                return
            }
        } catch (_: Throwable) {}

        val removalTime = System.currentTimeMillis()
        activeNavNotificationIdByPackage.remove(packageName)
        activeNavNotificationKeyByPackage.remove(packageName)
        lastPayloadHashByPackage.remove(packageName)
        // Conservar marca de tiempo de eliminación para impedir que una notificación tardía
        // con postTime anterior reactive una maniobra ya cancelada.
        lastPostTimeByPackage[packageName] = removalTime

        val payload = HashMap<String, Any?>()
        payload["packageName"] = packageName
        payload["notificationId"] = sbn.id
        payload["notificationKey"] = notificationKey
        payload["notificationCategory"] = sbn.notification?.category ?: "none"
        payload["title"] = null
        payload["text"] = null
        payload["subText"] = null
        payload["timestamp"] = removalTime
        payload["isRemoved"] = true

        notificationListener?.invoke(payload)
    }

    private fun extractTextsFromRemoteViews(
        packageName: String,
        notification: Notification,
        errorsOut: MutableList<String>
    ): List<String> {
        val result = mutableListOf<String>()
        @Suppress("DEPRECATION")
        val candidates = listOfNotNull(
            notification.bigContentView,
            notification.contentView,
            notification.headsUpContentView
        )
        if (candidates.isEmpty()) return emptyList()

        val pkgContext: Context = try {
            createPackageContext(packageName, Context.CONTEXT_IGNORE_SECURITY)
        } catch (_: Throwable) {
            applicationContext
        }

        for (rv in candidates) {
            try {
                val container = FrameLayout(pkgContext)
                val inflated: View = try {
                    rv.apply(pkgContext, container)
                } catch (_: Throwable) {
                    rv.apply(applicationContext, FrameLayout(applicationContext))
                }
                collectTextViews(inflated, result)
            } catch (e: Throwable) {
                errorsOut.add(e.javaClass.simpleName)
            }
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
        }
        val contentDesc = view.contentDescription?.toString()?.trim()
        if (!contentDesc.isNullOrEmpty() && !out.contains(contentDesc)) {
            out.add(contentDesc)
        }
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                collectTextViews(view.getChildAt(i), out)
            }
        }
    }
}
