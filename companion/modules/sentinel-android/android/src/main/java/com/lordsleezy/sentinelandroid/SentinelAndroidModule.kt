package com.lordsleezy.sentinelandroid

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

class SentinelAndroidModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("SentinelAndroid")

    AsyncFunction("requestCallScreeningRole") {
      requestCallScreeningRole()
    }

    AsyncFunction("getCallBlockingEnabled") {
      isCallScreeningRoleHeld()
    }

    AsyncFunction("getSpamNumbers") {
      SpamStore.getNumbers(context)
    }

    AsyncFunction("setSpamNumbers") { numbers: List<String> ->
      SpamStore.setNumbers(context, numbers)
    }

    AsyncFunction("auditAppPermissions") {
      auditAppPermissions()
    }

    AsyncFunction("estimateJunkBytes") {
      estimateJunkBytes()
    }

    AsyncFunction("clearJunkFiles") {
      clearJunkFiles()
    }
  }

  private val context: Context
    get() = requireNotNull(appContext.reactContext) { "React context unavailable" }

  private fun requestCallScreeningRole(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
    val roleManager = context.getSystemService(RoleManager::class.java) ?: return false
    if (!roleManager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) return false
    if (roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) return true
    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
    return false
  }

  private fun isCallScreeningRoleHeld(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
    val roleManager = context.getSystemService(RoleManager::class.java) ?: return false
    return roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
  }

  private fun auditAppPermissions(): List<Map<String, Any>> {
    val pm = context.packageManager
    val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
    } else {
      @Suppress("DEPRECATION")
      pm.getInstalledPackages(0)
    }

    val sensitive = listOf(
      android.Manifest.permission.CAMERA,
      android.Manifest.permission.RECORD_AUDIO,
      android.Manifest.permission.ACCESS_FINE_LOCATION,
      android.Manifest.permission.ACCESS_COARSE_LOCATION,
    )

    val results = mutableListOf<Map<String, Any>>()

    for (pkg in packages) {
      val appInfo = pkg.applicationInfo ?: continue
      if (appInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0) continue
      if (pkg.packageName == context.packageName) continue

      val granted = mutableListOf<String>()
      for (perm in sensitive) {
        val status = pm.checkPermission(perm, pkg.packageName)
        if (status == PackageManager.PERMISSION_GRANTED) {
          granted.add(friendlyPermission(perm))
        }
      }
      if (granted.isEmpty()) continue

      val suspicious = granted.size >= 2
      val label = pm.getApplicationLabel(appInfo).toString()
      results.add(
        mapOf(
          "packageName" to pkg.packageName,
          "appName" to label,
          "permissions" to granted,
          "suspicious" to suspicious,
        )
      )
    }

    return results.sortedWith(
      compareByDescending<Map<String, Any>> { it["suspicious"] as Boolean }
        .thenBy { it["appName"] as String }
    )
  }

  private fun friendlyPermission(perm: String): String = when (perm) {
    android.Manifest.permission.CAMERA -> "Camera"
    android.Manifest.permission.RECORD_AUDIO -> "Microphone"
    android.Manifest.permission.ACCESS_FINE_LOCATION,
    android.Manifest.permission.ACCESS_COARSE_LOCATION -> "Location"
    else -> perm.substringAfterLast('.')
  }

  private fun estimateJunkBytes(): Double {
    var total = 0L
    total += dirSize(context.cacheDir)
    context.externalCacheDir?.let { total += dirSize(it) }
    total += dirSize(File(context.cacheDir, "WebView"))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
      context.externalMediaDirs?.forEach { total += dirSize(it) }
    }
    return total.toDouble()
  }

  private fun clearJunkFiles(): Map<String, Any> {
    var freed = 0L
    freed += clearDir(context.cacheDir)
    context.externalCacheDir?.let { freed += clearDir(it) }
    freed += clearDir(File(context.cacheDir, "WebView"))
    val mb = freed / (1024.0 * 1024.0)
    val message = if (freed > 0) {
      String.format("Cleared %.1f MB of temporary files.", mb)
    } else {
      "Your phone is already tidy."
    }
    return mapOf("bytesFreed" to freed.toDouble(), "message" to message)
  }

  private fun dirSize(dir: File?): Long {
    if (dir == null || !dir.exists()) return 0L
    if (dir.isFile) return dir.length()
    return dir.listFiles()?.sumOf { dirSize(it) } ?: 0L
  }

  private fun clearDir(dir: File?): Long {
    if (dir == null || !dir.exists()) return 0L
    var freed = 0L
    if (dir.isFile) {
      freed = dir.length()
      dir.delete()
      return freed
    }
    dir.listFiles()?.forEach { child ->
      freed += clearDir(child)
    }
    return freed
  }
}
