package com.lordsleezy.sentinelandroid

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class SentinelCallScreeningService : CallScreeningService() {
  override fun onScreenCall(callDetails: Call.Details) {
    val number = callDetails.handle?.schemeSpecificPart ?: ""
    val block = SpamStore.shouldBlock(applicationContext, number)
    val response = CallResponse.Builder()
      .setDisallowCall(block)
      .setRejectCall(block)
      .setSkipCallLog(false)
      .setSkipNotification(block)
      .build()
    respondToCall(callDetails, response)
  }
}
