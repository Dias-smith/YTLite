package com.ytlite.player.data.extractor

import android.content.Context
import android.util.Log
import com.ytlite.player.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicReference

data class ExtractorRemoteConfig(
    val androidClientVersion: String = "20.10.38",
    val signatureTimestamp: Int = 20646,
    val preferItags: List<Int> = listOf(18, 22, 37),
    val enableAndroidPlayerFallback: Boolean = true,
    val enableWatchPageFallback: Boolean = true,
) {
    companion object {
        val DEFAULTS = ExtractorRemoteConfig()

        fun fromJson(obj: JSONObject?): ExtractorRemoteConfig {
            if (obj == null) return DEFAULTS
            val itags = mutableListOf<Int>()
            obj.optJSONArray("preferItags")?.let { arr ->
                for (i in 0 until arr.length()) {
                    itags.add(arr.optInt(i))
                }
            }
            return ExtractorRemoteConfig(
                androidClientVersion = obj.optString(
                    "androidClientVersion",
                    DEFAULTS.androidClientVersion,
                ),
                signatureTimestamp = obj.optInt(
                    "signatureTimestamp",
                    DEFAULTS.signatureTimestamp,
                ),
                preferItags = itags.ifEmpty { DEFAULTS.preferItags },
                enableAndroidPlayerFallback = obj.optBoolean(
                    "enableAndroidPlayerFallback",
                    DEFAULTS.enableAndroidPlayerFallback,
                ),
                enableWatchPageFallback = obj.optBoolean(
                    "enableWatchPageFallback",
                    DEFAULTS.enableWatchPageFallback,
                ),
            )
        }
    }
}

object ExtractorRemoteConfigStore {
    private val current = AtomicReference(ExtractorRemoteConfig.DEFAULTS)
    private const val PREFS = "extractor_remote_config"
    private const val KEY = "json"

    fun current(): ExtractorRemoteConfig = current.get()

    fun apply(config: ExtractorRemoteConfig, context: Context? = null) {
        current.set(config)
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.putString(KEY, toJson(config).toString())
            ?.apply()
    }

    fun restore(context: Context) {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null)
            ?: return
        runCatching {
            apply(ExtractorRemoteConfig.fromJson(JSONObject(raw)))
        }
    }

    private fun toJson(config: ExtractorRemoteConfig): JSONObject =
        JSONObject()
            .put("androidClientVersion", config.androidClientVersion)
            .put("signatureTimestamp", config.signatureTimestamp)
            .put("preferItags", org.json.JSONArray(config.preferItags))
            .put("enableAndroidPlayerFallback", config.enableAndroidPlayerFallback)
            .put("enableWatchPageFallback", config.enableWatchPageFallback)
}

/**
 * Downloads / caches remote extractor assets from Supabase Storage (no APK assets).
 */
class ExtractorBundleStore private constructor(
    private val appContext: Context,
) {
    sealed class BundleException(message: String) : Exception(message) {
        class NotConfigured : BundleException("Supabase URL is not configured; cannot download extractor")
        class DownloadFailed(msg: String) : BundleException("Extractor download failed: $msg")
        class ChecksumMismatch(file: String) : BundleException("Extractor checksum mismatch: $file")
        class Incomplete : BundleException("Extractor bundle incomplete")
        class AppVersionTooLow(required: String, current: String) :
            BundleException("App $current is too old for extractor (needs $required)")
        class InvalidManifest : BundleException("Invalid extractor manifest")
    }

    data class ManifestFile(val path: String, val sha256: String)
    data class Manifest(
        val version: Int,
        val minAppVersion: String,
        val files: Map<String, ManifestFile>,
        val config: ExtractorRemoteConfig?,
    )

    private val mutex = Mutex()
    @Volatile private var lastBackgroundCheckMs: Long = 0L

    suspend fun ensureBundle(backgroundRefresh: Boolean = true): File = mutex.withLock {
        withContext(Dispatchers.IO) {
            ExtractorRemoteConfigStore.restore(appContext)
            val dir = cacheDir()
            if (isComplete(dir)) {
                loadInstalledManifest(dir)?.let {
                    ExtractorRemoteConfigStore.apply(it.config ?: ExtractorRemoteConfig.DEFAULTS, appContext)
                }
                if (backgroundRefresh) {
                    scheduleBackgroundRefresh()
                }
                return@withContext dir
            }
            downloadAndInstall()
            cacheDir()
        }
    }

    fun cacheDir(): File {
        val dir = File(appContext.filesDir, "extractor")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun bridgeFileUrl(): String = "file://${cacheDir().absolutePath}/bridge.html"

    private fun scheduleBackgroundRefresh() {
        val now = System.currentTimeMillis()
        if (now - lastBackgroundCheckMs < 60_000L) return
        lastBackgroundCheckMs = now
        // Caller already on IO / coroutine; fire-and-forget via new job from Application scope ideally.
        // Here we do a synchronous best-effort only when explicitly awaited elsewhere.
    }

    suspend fun refreshIfNewer() = withContext(Dispatchers.IO) {
        mutex.withLock {
            val remote = fetchManifest()
            val installed = loadInstalledManifest(cacheDir())?.version ?: 0
            if (remote.version > installed) {
                install(remote)
            }
        }
    }

    private suspend fun downloadAndInstall() {
        val remote = fetchManifest()
        install(remote)
    }

    private fun install(manifest: Manifest) {
        checkMinAppVersion(manifest.minAppVersion)
        val required = listOf("extractor.js", "bridge.html", "bridge-ios.html")
        required.forEach { name ->
            if (!manifest.files.containsKey(name)) throw BundleException.InvalidManifest()
        }

        val dir = cacheDir()
        val staging = File(dir, ".staging-${System.nanoTime()}")
        if (staging.exists()) staging.deleteRecursively()
        staging.mkdirs()
        try {
            for (name in required) {
                val entry = manifest.files.getValue(name)
                val bytes = downloadPublicObject(entry.path)
                val hex = sha256Hex(bytes)
                if (!hex.equals(entry.sha256, ignoreCase = true)) {
                    throw BundleException.ChecksumMismatch(name)
                }
                File(staging, name).writeBytes(bytes)
            }
            File(staging, "installed-manifest.json").writeText(manifestToJson(manifest).toString())
            for (name in required + "installed-manifest.json") {
                val src = File(staging, name)
                val dest = File(dir, name)
                if (dest.exists()) dest.delete()
                if (!src.renameTo(dest)) {
                    src.copyTo(dest, overwrite = true)
                    src.delete()
                }
            }
            staging.deleteRecursively()
            ExtractorRemoteConfigStore.apply(
                manifest.config ?: ExtractorRemoteConfig.DEFAULTS,
                appContext,
            )
            Log.i(TAG, "installed extractor version=${manifest.version}")
        } catch (e: Exception) {
            staging.deleteRecursively()
            throw e
        }
    }

    private fun fetchManifest(): Manifest {
        val url = publicUrl("manifest.json")
        val bytes = httpGet(url)
        return parseManifest(String(bytes, Charsets.UTF_8))
    }

    private fun downloadPublicObject(relativePath: String): ByteArray =
        httpGet(publicUrl(relativePath))

    private fun publicUrl(relativePath: String): String {
        val base = BuildConfig.SUPABASE_URL.trimEnd('/')
        if (base.isBlank()) throw BundleException.NotConfigured()
        val path = relativePath.trimStart('/')
        return "$base/storage/v1/object/public/extractor/$path"
    }

    private fun httpGet(url: String): ByteArray {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 30_000
            readTimeout = 45_000
        }
        try {
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val bytes = stream?.readBytes() ?: ByteArray(0)
            if (code !in 200..299 || bytes.isEmpty()) {
                throw BundleException.DownloadFailed("HTTP $code for $url")
            }
            return bytes
        } finally {
            conn.disconnect()
        }
    }

    private fun isComplete(dir: File): Boolean {
        val required = listOf(
            "extractor.js",
            "bridge.html",
            "bridge-ios.html",
            "installed-manifest.json",
        )
        return required.all { File(dir, it).isFile && File(dir, it).length() > 0L }
    }

    private fun loadInstalledManifest(dir: File): Manifest? {
        val file = File(dir, "installed-manifest.json")
        if (!file.isFile) return null
        return runCatching { parseManifest(file.readText()) }.getOrNull()
    }

    private fun parseManifest(raw: String): Manifest {
        val root = JSONObject(raw)
        val filesObj = root.optJSONObject("files") ?: throw BundleException.InvalidManifest()
        val files = mutableMapOf<String, ManifestFile>()
        for (key in filesObj.keys()) {
            val entry = filesObj.getJSONObject(key)
            files[key] = ManifestFile(
                path = entry.getString("path"),
                sha256 = entry.getString("sha256"),
            )
        }
        return Manifest(
            version = root.getInt("version"),
            minAppVersion = root.optString("minAppVersion", "1.0.0"),
            files = files,
            config = ExtractorRemoteConfig.fromJson(root.optJSONObject("config")),
        )
    }

    private fun manifestToJson(manifest: Manifest): JSONObject {
        val files = JSONObject()
        manifest.files.forEach { (name, entry) ->
            files.put(
                name,
                JSONObject().put("path", entry.path).put("sha256", entry.sha256),
            )
        }
        val config = ExtractorRemoteConfigStore.current().let { c ->
            JSONObject()
                .put("androidClientVersion", c.androidClientVersion)
                .put("signatureTimestamp", c.signatureTimestamp)
                .put("preferItags", org.json.JSONArray(c.preferItags))
                .put("enableAndroidPlayerFallback", c.enableAndroidPlayerFallback)
                .put("enableWatchPageFallback", c.enableWatchPageFallback)
        }
        // Prefer manifest's own config when writing installed copy.
        val cfg = manifest.config?.let {
            JSONObject()
                .put("androidClientVersion", it.androidClientVersion)
                .put("signatureTimestamp", it.signatureTimestamp)
                .put("preferItags", org.json.JSONArray(it.preferItags))
                .put("enableAndroidPlayerFallback", it.enableAndroidPlayerFallback)
                .put("enableWatchPageFallback", it.enableWatchPageFallback)
        } ?: config
        return JSONObject()
            .put("version", manifest.version)
            .put("minAppVersion", manifest.minAppVersion)
            .put("files", files)
            .put("config", cfg)
    }

    private fun checkMinAppVersion(required: String) {
        val current = runCatching {
            val p = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
            @Suppress("DEPRECATION")
            p.versionName ?: "0"
        }.getOrDefault("0")
        if (compareSemver(current, required) < 0) {
            throw BundleException.AppVersionTooLow(required, current)
        }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    /** @return negative if a < b */
    private fun compareSemver(a: String, b: String): Int {
        val pa = a.split('.').map { it.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { it.toIntOrNull() ?: 0 }
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return 0
    }

    companion object {
        private const val TAG = "ExtractorBundle"

        @Volatile
        private var instance: ExtractorBundleStore? = null

        fun getInstance(context: Context): ExtractorBundleStore =
            instance ?: synchronized(this) {
                instance ?: ExtractorBundleStore(context.applicationContext).also { instance = it }
            }
    }
}
