package br.clickdireto.app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * ClickDireto V2 (Android) — tela única de operação:
 * conectar (Iniciar sessão) → disparar pelo botão físico da câmera →
 * cada JPEG novo entra, aparece em destaque e é salvo no álbum "ClickDireto".
 */
class MainActivity : AppCompatActivity() {

    private lateinit var stateText: TextView
    private lateinit var counterText: TextView
    private lateinit var heroImage: ImageView
    private lateinit var heroMessage: TextView
    private lateinit var infoText: TextView
    private lateinit var scrollThumbs: HorizontalScrollView
    private lateinit var thumbRow: LinearLayout
    private lateinit var startButton: Button
    private lateinit var endButton: Button
    private lateinit var logLink: TextView

    private lateinit var controller: CameraTetherController
    private val logLines = StringBuilder()
    private var photosReceived = 0

    private val detachReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE) ?: return
            if (controller.isCamera(device)) {
                appendLog("Cabo: câmera desconectada pelo usuário.")
                setState("Câmera removida — reconecte o cabo", 0)
                controller.stopSession()
            }
        }
    }

    private val listener = object : TetherListener {
        override fun onStateChanged(text: String, kind: Int) = setState(text, kind)
        override fun onCatalogRead(existingPhotos: Int) {
            appendLog("Catálogo: $existingPhotos fotos já no cartão — não serão reimportadas.")
            infoText.text = "Fotos já no cartão: $existingPhotos — não serão importadas."
        }
        override fun onPhotoImported(hero: android.graphics.Bitmap, thumb: android.graphics.Bitmap, displayName: String, latencySec: Double) {
            photosReceived++
            counterText.text = photosReceived.toString()
            heroImage.visibility = View.VISIBLE
            heroMessage.visibility = View.GONE
            heroImage.setImageBitmap(hero)
            infoText.text = String.format(
                Locale.getDefault(),
                "Última: %s — detectada→galeria %.2f s",
                displayName, latencySec
            )
            addThumbnail(thumb)
        }
        override fun onSessionError(message: String) {
            appendLog("ERRO: $message")
            setState("Erro: $message", 2)
        }
        override fun onDisconnected() {
            appendLog("Sessão encerrada.")
            setState("Desconectado", 0)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        stateText = findViewById(R.id.stateText)
        counterText = findViewById(R.id.counterText)
        heroImage = findViewById(R.id.heroImage)
        heroMessage = findViewById(R.id.heroMessage)
        infoText = findViewById(R.id.infoText)
        scrollThumbs = findViewById(R.id.scrollThumbs)
        thumbRow = findViewById(R.id.thumbRow)
        startButton = findViewById(R.id.startButton)
        endButton = findViewById(R.id.endButton)
        logLink = findViewById(R.id.logLink)

        controller = CameraTetherController(applicationContext)
        controller.listener = listener
        controller.log = { line -> appendLog(line) }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 11)
        }
        ContextCompat.registerReceiver(
            this, detachReceiver,
            IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED),
            ContextCompat.RECEIVER_EXPORTED
        )

        startButton.setOnClickListener {
            appendLog("Usuário pediu início de sessão.")
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            controller.startFromUser()
        }
        endButton.setOnClickListener {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            controller.stopSession()
        }
        logLink.setOnClickListener { showLogDialog() }

        // Alarme rico: se o cabo for conectado com o app aberto, conectar já.
        intent?.let { handleAttachIntent(it) }
        setState("Desconectado — conecte a câmera", 0)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAttachIntent(intent)
    }

    private fun handleAttachIntent(intent: Intent) {
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            controller.onUsbAttached(device)
        }
    }

    override fun onResume() {
        super.onResume()
        // Conexão automática: se a permissão já foi concedida antes, abre sessão direto.
        val camera = controller.findCamera()
        if (camera != null && controller.hasPermission(camera) &&
            photosReceived == 0 && stateText.text.toString().startsWith("Desconectado")) {
            appendLog("Câmera já autoraizada: reconectando automaticamente.")
            controller.startFromUser()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(detachReceiver) } catch (_: Exception) {}
        controller.shutdown()
    }

    // ------------------------------------------------------------- UI helpers

    private fun setState(text: String, kind: Int) {
        runOnUiThread {
            when (kind) {
                1 -> stateText.setTextColor(ContextCompat.getColor(this, R.color.cdOk))
                2 -> stateText.setTextColor(ContextCompat.getColor(this, R.color.cdFail))
                else -> stateText.setTextColor(ContextCompat.getColor(this, R.color.cdText))
            }
            stateText.text = text
        }
        appendLog(text)
    }

    private fun addThumbnail(bitmap: android.graphics.Bitmap) {
        runOnUiThread {
            scrollThumbs.visibility = View.VISIBLE
            val size = resources.displayMetrics.heightPixels / 24  // aproxima 46dp
            val side = size.coerceIn(90, 140)
            val iv = ImageView(this)
            iv.setImageBitmap(bitmap)
            iv.scaleType = ImageView.ScaleType.CENTER_CROP
            val margin = (side / 10)
            val params = LinearLayout.LayoutParams(side, side)
            params.setMargins(margin, 0, margin, 0)
            iv.layoutParams = params
            iv.clipToOutline = true
            iv.background = bluishFrame()
            iv.setOnClickListener {
                val heroBitmap = (iv.drawable as? BitmapDrawable)?.bitmap ?: return@setOnClickListener
                heroImage.setImageBitmap(heroBitmap)
            }
            thumbRow.addView(iv, 0)
            if (thumbRow.childCount > 10) thumbRow.removeViewAt(thumbRow.childCount - 1)
        }
    }

    private fun bluishFrame(): android.graphics.drawable.Drawable {
        val drawable = ContextCompat.getDrawable(this, R.drawable.bg_statepill)
        return drawable ?:android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
    }

    private fun appendLog(line: String) {
        runOnUiThread {
            val timestamp = android.text.format.DateFormat.format("HH:mm:ss", java.util.Date())
            logLines.append("[").append(timestamp).append("] ").append(line).append('\n')
        }
    }

    private fun showLogDialog() {
        runOnUiThread {
            val view = ScrollViewContainer(this, logLines.toString())
            AlertDialog.Builder(this)
                .setTitle("Diagnóstico")
                .setView(view)
                .setPositiveButton("Fechar", null)
                .show()
        }
    }

    private class ScrollViewContainer(context: Context, text: String) : android.widget.ScrollView(context) {
        init {
            val display = TextView(context)
            display.text = text
            display.setPadding(40, 24, 40, 24)
            display.textSize = 11f
            display.setTextColor(ContextCompat.getColor(context, R.color.cdText))
            display.typeface = android.graphics.Typeface.MONOSPACE
            addView(display)
        }
    }
}
