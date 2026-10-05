package com.unitec.unitec_forca_vendas

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * FragmentActivity (biometria) + envio de PDF direto ao chat do WhatsApp.
 *
 * O extra "jid" ({telefone}@s.whatsapp.net) só resolve se já existir conversa
 * com o número; caso contrário o WhatsApp abre a lista "Enviar para…".
 * Ainda assim evitamos a folha genérica do Android (Share sheet).
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.unitec.forca_vendas/whatsapp"
    private val updaterChannelName = "com.unitec.forca_vendas/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canInstall" -> result.success(canInstallPackages())
                        "openInstallSettings" -> result.success(openInstallSettings())
                        "apkInfo" -> result.success(apkInfo(call.argument<String>("path").orEmpty()))
                        "installApk" -> result.success(installApk(call.argument<String>("path").orEmpty()))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("UPDATER", e.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(whatsAppPackage() != null)
                    "sharePdf" -> {
                        val phone = call.argument<String>("phone").orEmpty()
                        val path = call.argument<String>("path").orEmpty()
                        val text = call.argument<String>("text").orEmpty()
                        try {
                            result.success(sharePdfToWhatsApp(phone, path, text))
                        } catch (e: Exception) {
                            result.error("WHATSAPP", e.message, null)
                        }
                    }
                    "openChat" -> {
                        val phone = call.argument<String>("phone").orEmpty()
                        val text = call.argument<String>("text").orEmpty()
                        try {
                            result.success(openWhatsAppChat(phone, text))
                        } catch (e: Exception) {
                            result.error("WHATSAPP", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun whatsAppPackage(): String? {
        val pm = packageManager
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            try {
                pm.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: PackageManager.NameNotFoundException) {
                // tenta o próximo
            }
        }
        return null
    }

    private fun openWhatsAppChat(phone: String, text: String): Boolean {
        val digits = phone.filter { it.isDigit() }
        if (digits.length < 10) return false
        val encoded = Uri.encode(text)
        val uri = Uri.parse(
            if (text.isBlank()) "https://wa.me/$digits"
            else "https://wa.me/$digits?text=$encoded",
        )
        val intent = Intent(Intent.ACTION_VIEW, uri)
        whatsAppPackage()?.let { intent.setPackage(it) }
        startActivity(intent)
        return true
    }

    private fun sharePdfToWhatsApp(phone: String, path: String, text: String): Boolean {
        val pkg = whatsAppPackage() ?: return false
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return false

        val digits = phone.filter { it.isDigit() }
        if (digits.length < 10) return false

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            setPackage(pkg)
            putExtra(Intent.EXTRA_STREAM, uri)
            if (text.isNotBlank()) {
                putExtra(Intent.EXTRA_TEXT, text)
            }
            // Roteia para o chat do número (quando a conversa já existe no WhatsApp).
            putExtra("jid", "$digits@s.whatsapp.net")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(contentResolver, "pdf", uri)
        }
        grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(intent)
        return true
    }

    // ---- Atualização do APK (GitHub Release) -------------------------------

    /** Android 8+: o usuário precisa liberar "Permitir desta fonte" para este app. */
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
        return true
    }

    /** Pacote e versão do APK baixado (o app só instala se for ele mesmo e mais novo). */
    private fun apkInfo(path: String): Map<String, Any?>? {
        val file = File(path)
        if (!file.exists()) return null
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(path, 0)
        } ?: return null
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to code,
            "versionName" to info.versionName,
            "currentPackage" to packageName,
        )
    }

    /** Abre o instalador padrão do Android (o usuário confirma a atualização). */
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return false
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return true
    }
}
