package com.lordsleezy.sentinelandroid

import android.content.Context

object SpamStore {
  private const val PREFS = "sentinel_spam"
  private const val KEY_NUMBERS = "numbers"

  fun getNumbers(context: Context): List<String> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_NUMBERS, "") ?: ""
    return raw.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
  }

  fun setNumbers(context: Context, numbers: List<String>) {
    val cleaned = numbers.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(KEY_NUMBERS, cleaned.joinToString("\n"))
      .apply()
  }

  fun shouldBlock(context: Context, number: String): Boolean {
    val normalized = normalize(number)
    if (normalized.isEmpty()) return false
    return getNumbers(context).any { normalize(it) == normalized || normalized.endsWith(normalize(it)) }
  }

  private fun normalize(number: String): String {
    return number.replace(Regex("[^0-9+]"), "")
  }
}
