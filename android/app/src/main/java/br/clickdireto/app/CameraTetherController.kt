package br.clickdireto.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.mtp.MtpConstants
import android.mtp.MtpDevice
import android.mtp.MtpEvent
import android.mtp.MtpObjectInfo
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.io.File
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Callbacks entregues SEMPRE na thread principal.
 */
interface TetherListener {
    /** kind: 0 = neutro, 1 = sucesso/ativo, 2 = erro. */
    fun onStateChanged(text: String, kind: Int)
    fun onCatalogRead(existingPhotos: Int)
    fun onPhotoImported(hero: Bitmap, thumb: Bitmap, displayName: String, latencySec: Double)
    fun onSessionError(message: String)
    fun onDisconnected()
}

/**
 * Detecção USB, permissão, sessão MTP com a câmera, eventos de nova foto
 * (EVENT_OBJECT_ADDED via readEvent — o mecanismo nativo do protocolo PTP),
 * fila serial de importação, varredura de seguranca e salvamento na galeria.
 *
 * Regras do projeto: NUNCA apagar do cartão; NUNCA reimportar o que já existia;
 * sem internet; só JPEG.
 */
class CameraTetherController(private val appContext: Context) {

    companion object {
        const val USB_PERMISSION = "br.clickdireto.app.USB_PERMISSION"
        const val CANON_VENDOR_ID = 1193 // 0x04A9 — Canon Inc.
        const val MAX_HERO_DIMENSION = 2048
        const val MAX_THUMB_DIMENSION = 240
    }

    var listener: TetherListener? = null
    var log: ((String) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val usbManager = appContext.getSystemService(Context.USB_SERVICE) as UsbManager
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var session: CanonSession? = null
    private var permissionReceiver: BroadcastReceiver? = null
    private var photosReceived = 0
    private var avgLatency = 0.0
    private var latencySamples = 0

    // ------------------------------------------------------------------ USB

    fun isCamera(device: UsbDevice): Boolean {
        if (device.vendorId == CANON_VENDOR_ID) return true
        if (device.deviceClass == UsbConstants.USB_CLASS_STILL_IMAGE) return true
        for (index in 0 until device.interfaceCount) {
            if (device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) return true
        }
        return false
    }

    fun findCamera(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { isCamera(it) }

    fun hasPermission(device: UsbDevice): Boolean =
        usbManager.hasPermission(device)

    /** Chamar quando o usuário tocar em "Iniciar sessão". */
    fun startFromUser() {
        val camera = findCamera()
        if (camera == null) {
            postState("Conecte a câmera pelo cabo USB", 0)
            log?.invoke("Nenhuma câmera USB encontrada ainda.")
            return
        }
        log?.invoke("Câmera encontrada: ${camera.deviceName} (vendor ${camera.vendorId}, product ${camera.productId})")
        if (hasPermission(camera)) {
            startSession(camera)
        } else {
            requestPermission(camera)
        }
    }

    fun onUsbAttached(device: UsbDevice?) {
        if (device != null && isCamera(device)) {
            log?.invoke("USB: câmera conectada ao cabo (vendor ${device.vendorId}).")
            val active = session != null
            if (!active) requestPermission(device)
        }
    }

    fun requestPermission(device: UsbDevice) {
        postState("Aguardando autorização USB…", 0)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val intent = PendingIntent.getBroadcast(
            appContext, 0,
            Intent(USB_PERMISSION).setPackage(appContext.packageName), flags
        )
        if (permissionReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action != USB_PERMISSION) return
                    try { context.unregisterReceiver(this) } catch (_: Exception) {}
                    permissionReceiver = null
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val deviceId = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)?.deviceId
                    if (granted) {
                        val camera = usbManager.deviceList.values
                            .firstOrNull { it.deviceId == deviceId } ?: findCamera()
                        if (camera != null) startSession(camera)
                    } else {
                        postState("Autorização negada", 2)
                        log?.invoke("ERRO: permissão USB negada pelo usuário.")
                    }
                }
            }
            permissionReceiver = receiver
            ContextCompat.registerReceiver(
                appContext, receiver,
                IntentFilter(USB_PERMISSION),
                ContextCompat.RECEIVER_EXPORTED
            )
        }
        usbManager.requestPermission(device, intent)
        log?.invoke("Solicitando autorização USB (prompt do sistema)…")
    }

    // -------------------------------------------------------------- Sessão

    private fun startSession(camera: UsbDevice) {
        if (session != null) {
            log?.invoke("Sessão já está aberta.")
            return
        }
        postState("Preparando conexão…", 0)
        ioExecutor.execute {
            val newSession = CanonSession(camera)
            if (!newSession.open()) {
                ioExecutor.execute { newSession.stop() }
                return@execute
            }
            session = newSession
            newSession.boot()
        }
    }

    fun stopSession() {
        val closing = session
        session = null
        closing?.stop()
        postState("Desconectado", 0)
        log?.invoke("Sessão encerrada pelo usuário.")
    }

    fun shutdown() {
        stopSession()
        permissionReceiver?.let {
            try { appContext.unregisterReceiver(it) } catch (_: Exception) {}
        }
        permissionReceiver = null
        ioExecutor.shutdown()
    }

    private inner class CanonSession(private val device: UsbDevice) {

        private val mtp = MtpDevice(device)
        private var connection: UsbDeviceConnection? = null
        private var connectionClosed = false
        private val running = AtomicBoolean(false)
        private val cancelSignal = CancellationSignal()
        private val seenHandles = Collections.synchronizedSet(HashSet<Int>())
        private val scheduler = Executors.newSingleThreadScheduledExecutor()
        private var eventThread: Thread? = null

        /** Ouve eventos de nova foto (bloqueante) numa thread dedicada. */
        private fun eventLoop() {
            log?.invoke("Laço de eventos PTP iniciado (readEvent bloqueante).")
            while (running.get()) {
                try {
                    val event = mtp.readEvent(cancelSignal)
                    when (event.eventCode) {
                        MtpEvent.EVENT_OBJECT_ADDED -> {
                            // MtpEvent nao expoe o handle adicionado (so getEventCode/getDevicePropCode);
                            // o evento serve de gatilho: fazemos a diferenca de handles agora.
                            importNewHandlesByDiff("evento PTP OBJECT_ADDED")
                        }
                    }
                } catch (canceled: android.os.OperationCanceledException) {
                    break
                } catch (e: Exception) {
                    if (running.get()) {
                        main.post {
                            log?.invoke("ERRO no laço de eventos: ${e.message}")
                        }
                        importFallbackIfRunning()
                        break
                    } else {
                        break
                    }
                }
            }
            log?.invoke("Laço de eventos encerrado.")
        }

        /** Fallback: varredura de handles (caso a câmera não dispare o evento). */
        private fun importNewHandlesByDiff(source: String) {
            try {
                val storageIds = mtp.getStorageIds() ?: return
                if (storageIds.isEmpty()) return
                val handles = mtp.getObjectHandles(storageIds[0], 0, 0) ?: return
                for (handle in handles) {
                    if (!seenHandles.contains(handle)) {
                        importIfNew(handle, source)
                    }
                }
            } catch (e: Exception) {
                log?.invoke("ERRO na varredura: ${e.message}")
            }
        }

        private fun importFallbackIfRunning() {
            if (running.get()) scheduler.execute { importNewHandlesByDiff("varredura após interrupção") }
        }

        fun open(): Boolean {
            return try {
                val conn = usbManager.openDevice(device)
                if (conn == null) {
                    main.post { listener?.onSessionError("Conexão USB não pôde ser aberta") }
                    return false
                }
                connection = conn
                val opened = mtp.open(conn)
                if (!opened) {
                    main.post { listener?.onSessionError("Câmera recusou a sessão MTP/PTP") }
                    connection?.let { if (!connectionClosed) { it.close(); connectionClosed = true } }
                    return false
                }
                true
            } catch (e: Exception) {
                main.post { listener?.onSessionError("Falha de abertura: ${e.message}") }
                false
            }
        }

        fun boot() {
            try {
                val storageIds = mtp.getStorageIds()
                log?.invoke("Armazenamentos: ${storageIds?.joinToString()}")
                val storage = storageIds?.firstOrNull() ?: 0
                val handles = mtp.getObjectHandles(storage, 0, 0) ?: IntArray(0)
                val jpegs = handles.filter { isJpegHandle(it) }
                synchronized(seenHandles) {
                    seenHandles.clear()
                    handles.forEach { seenHandles.add(it) }
                }
                main.post {
                    listener?.onCatalogRead(jpegs.size)
                    listener?.onStateChanged("Conectada — pronto para fotografar", 1)
                }
                log?.invoke("Catálogo lido: ${jpegs.size} fotos no cartão — nenhuma será reimportada.")
            } catch (e: Exception) {
                main.post { listener?.onSessionError("Catálogo: ${e.message}") }
            }
            running.set(true)
            eventThread = Thread({ eventLoop() }, "ClickDireto-events").apply { start() }
            scheduler.scheduleWithFixedDelay(
                { if (running.get()) importNewHandlesByDiff("varredura de seguranca (3 s)") },
                3, 3, TimeUnit.SECONDS
            )
        }

        fun stop() {
            if (!running.compareAndSet(true, false)) {
                cleanup()
                return
            }
            try { cancelSignal.cancel() } catch (_: Exception) {}
            scheduler.shutdownNow()
            cleanup()
            main.post { listener?.onDisconnected() }
        }

        private fun cleanup() {
            try { mtp.close() } catch (_: Exception) {}
            connection?.let { if (!connectionClosed) { it.close(); connectionClosed = true } }
        }

        private fun isJpegHandle(handle: Int): Boolean {
            val info = try { mtp.getObjectInfo(handle) } catch (_: Exception) { null } ?: return false
            return isJpegInfo(info)
        }

        private fun isJpegInfo(info: MtpObjectInfo): Boolean {
            if (info.format == MtpConstants.FORMAT_EXIF_JPEG) return true
            val name = info.name?.lowercase() ?: return false
            return name.endsWith(".jpg") || name.endsWith(".jpeg")
        }

        /** Fila serial: capturas entram aqui, impessoal e em ordem. */
        private fun importIfNew(handle: Int, source: String) {
            if (!seenHandles.add(handle)) return
            val info = try { mtp.getObjectInfo(handle) } catch (_: Exception) { null }
            if (info == null) {
                log?.invoke("Detectado handle $handle sem Info; ignorado.")
                return
            }
            if (!isJpegInfo(info)) {
                log?.invoke("Novo objeto $handle não é JPEG (${info.format}); ignorado.")
                return
            }
            val startedAt = SystemClock.elapsedRealtime()
            val safeName = sanitizeName(info.name ?: "IMG_$handle.jpg")
            val dir = File(appContext.cacheDir, "imports").apply { if (!exists()) mkdirs() }
            val dest = File(dir, safeName)
            val ok = try {
                mtp.importFile(handle, dest.absolutePath)
            } catch (e: Exception) {
                log?.invoke("ERRO no importFile: ${e.message}")
                false
            }
            if (!ok) {
                seenHandles.remove(handle)
                main.post { listener?.onSessionError("Download do JPEG falhou (handle $handle)") }
                return
            }
            val detectedSec = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
            log?.invoke(
                String.format(
                    "NOVA FOTO: %s (%.1f KB) — origem %s — baixada em %.2f s",
                    safeName, dest.length() / 1024.0, source, detectedSec
                )
            )
            // getDateCreated() ja vem em milissegundos desde 1970 (docs oficiais) — sem parse.
            val rawDate = info.dateCreated
            val dateTaken: Long? = if (rawDate > 0L) rawDate else null
            val saveOutcome = GalleryWriter.saveJpeg(appContext, dest, dateTaken)
            val totalSec = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
            saveOutcome.fold(
                onSuccess = { savedPath ->
                    val decodedHero = decodeScaled(dest, MAX_HERO_DIMENSION)
                    val decodedThumb = decodeScaled(dest, MAX_THUMB_DIMENSION) ?: decodedHero
                    try { dest.delete() } catch (_: Exception) {}
                    if (decodedHero == null) {
                        main.post { listener?.onSessionError("Arquivo baixado não abriu como imagem") }
                        log?.invoke("ERRO: decodificação de imagem falhou.")
                        return
                    }
                    val hero: Bitmap = decodedHero
                    val thumb: Bitmap = decodedThumb ?: hero
                    photosReceived++
                    latencySamples++
                    avgLatency += (totalSec - avgLatency) / latencySamples
                    log?.invoke(
                        String.format(
                            "OK #%d — salvo em %s — detectada→galeria %.2f s (média %.2f s)",
                            photosReceived, savedPath, totalSec, avgLatency
                        )
                    )
                    val count = photosReceived
                    val average = avgLatency
                    main.post {
                        listener?.onPhotoImported(hero, thumb, safeName, if (latencySamples == 1) totalSec else average)
                        listener?.onStateChanged("Foto #$count salva na galeria", 1)
                    }
                },
                onFailure = { error ->
                    log?.invoke("ERRO ao salvar na galeria: ${error.message}")
                    main.post { listener?.onSessionError("Salvar na galeria falhou: ${error.message}") }
                }
            )
        }

        private fun decodeScaled(file: File, maxDimension: Int): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                var sample = 1
                val bigger = maxOf(bounds.outWidth, bounds.outHeight)
                while (bigger / (sample * 2) >= maxDimension) sample *= 2
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                BitmapFactory.decodeFile(file.absolutePath, options)
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun sanitizeName(raw: String): String {
        val cleaned = raw.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return if (cleaned.endsWith(".jpg", true) || cleaned.endsWith(".jpeg", true)) {
            cleaned
        } else {
            cleaned + ".jpg"
        }
    }

    private fun postState(text: String, kind: Int) {
        main.post { listener?.onStateChanged(text, kind) }
    }
}
