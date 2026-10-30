package br.clickdireto.app

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Salva o JPEG importado da câmera na galeria do sistema, na pasta
 * DCIM/ClickDireto (o app de galeria trata a pasta como "álbum ClickDireto").
 * Não recomprime, não apaga nada da câmera, não sobrescreve arquivos.
 */
object GalleryWriter {

    const val RELATIVE_PATH = "DCIM/ClickDireto"

    /**
     * @return resultado com o caminho/pasta em que foi gravado, para a UI.
     */
    fun saveJpeg(context: Context, tempFile: File, dateTakenMs: Long?): Result<String> {
        if (!tempFile.exists() || tempFile.length() == 0L) {
            return Result.failure(IllegalStateException("Arquivo vazio: ${tempFile.name}"))
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, tempFile, dateTakenMs)
        } else {
            saveLegacy(context, tempFile, dateTakenMs)
        }
    }

    private fun saveViaMediaStore(context: Context, tempFile: File, dateTakenMs: Long?): Result<String> {
        val resolver = context.contentResolver
        val displayName = tempFile.name

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, RELATIVE_PATH)
            if (dateTakenMs != null) {
                put(MediaStore.Images.Media.DATE_TAKEN, dateTakenMs)
                put(MediaStore.Images.Media.DATE_ADDED, dateTakenMs / 1000)
            }
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri: Uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return Result.failure(IllegalStateException("Galeria recusou a gravação (sem espaço/permissão?)"))
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                tempFile.inputStream().use { it.copyTo(out) }
            } ?: return Result.failure(IllegalStateException("Não foi possível abrir a galeria para escrever"))
            val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
            if (tempFile.length() == 0L) {
                Result.failure(IllegalStateException("Gravação terminou com 0 bytes"))
            } else {
                Result.success("$RELATIVE_PATH/$displayName")
            }
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            Result.failure(e)
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(context: Context, tempFile: File, dateTakenMs: Long?): Result<String> {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
            "ClickDireto"
        ).apply { if (!exists()) mkdirs() }
        val dest = File(dir, tempFile.name)
        return try {
            FileOutputStream(dest).use { out -> tempFile.inputStream().use { it.copyTo(out) } }
            if (dateTakenMs != null) {
                SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(dateTakenMs)).let { }
            }
            android.media.MediaScannerConnection.scanFile(
                context, arrayOf(dest.absolutePath), arrayOf("image/jpeg"), null
            )
            Result.success(dest.absolutePath)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /** Parse defensivo da data PTP (formato tipicamente yyyyMMddHHmmss). */
    fun parsePtpDate(raw: String?): Long? {
        val digits = raw?.filter { it.isDigit() } ?: return null
        val formats = listOf("yyyyMMddHHmmss", "yyyyMMddHHmm")
        for (fmt in formats) {
            if (digits.length == fmt.length) {
                return try {
                    SimpleDateFormat(fmt, Locale.US).parse(digits)?.time
                } catch (_: Exception) {
                    null
                }
            }
        }
        return null
    }
}
