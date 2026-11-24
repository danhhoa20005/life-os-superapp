package vn.lifeos.app.life_os

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RemoteViews
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToLong

object LifeOsWidgetStore {
    const val PREFS_NAME = "lifeos_home_widgets_prefs"
    const val KEY_QUEUED_COMMANDS_JSON = "queued_widget_commands_json"
    private const val KEY_LAST_UNDOABLE_JSON = "last_undoable_widget_cmd_json"

    // Legacy / Explicit Open-App Actions (bound ONLY to small corner brand icons)
    const val ACTION_VOICE_CAPTURE = "vn.lifeos.app.WIDGET_ACTION_VOICE_CAPTURE"
    const val ACTION_VOICE_SPLIT = "vn.lifeos.app.WIDGET_ACTION_VOICE_SPLIT"
    const val ACTION_OPEN_TODAY = "vn.lifeos.app.WIDGET_ACTION_OPEN_TODAY"
    const val ACTION_OPEN_FINANCE = "vn.lifeos.app.WIDGET_ACTION_OPEN_FINANCE"
    const val ACTION_OPEN_FAMILY = "vn.lifeos.app.WIDGET_ACTION_OPEN_FAMILY"

    // Direct On-Home-Screen Broadcast Actions (0 Activity Launch — Instant RemoteViews Update!)
    const val ACTION_BG_QUICK_EXPENSE = "vn.lifeos.app.WIDGET_BG_QUICK_EXPENSE"
    const val ACTION_BG_UNDO_LAST = "vn.lifeos.app.WIDGET_BG_UNDO_LAST"
    const val ACTION_BG_TOGGLE_MASK = "vn.lifeos.app.WIDGET_BG_TOGGLE_MASK"
    const val ACTION_BG_CYCLE_WEALTH_MODE = "vn.lifeos.app.WIDGET_BG_CYCLE_WEALTH_MODE"
    const val ACTION_BG_GROUP_MEMBER_DELTA = "vn.lifeos.app.WIDGET_BG_GROUP_MEMBER_DELTA"
    const val ACTION_BG_QUICK_GROUP_SPLIT = "vn.lifeos.app.WIDGET_BG_QUICK_GROUP_SPLIT"
    const val ACTION_BG_TOGGLE_SAFE_MODE = "vn.lifeos.app.WIDGET_BG_TOGGLE_SAFE_MODE"
    const val ACTION_BG_QUICK_WATER = "vn.lifeos.app.WIDGET_BG_QUICK_WATER"

    @Volatile
    var onBackgroundWidgetCommandPing: (() -> Unit)? = null

    private fun pendingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    /**
     * Builds a `PendingIntent.getBroadcast` that executes right on the Android Home Screen
     * without ever pushing the user into `MainActivity`.
     */
    fun buildBroadcastPendingIntent(
        context: Context,
        action: String,
        reqCode: Int,
        extras: Bundle? = null
    ): PendingIntent {
        val intent = Intent(context, LifeOsWidgetActionReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("lifeos://widget_bg/$action/$reqCode")
            if (extras != null) {
                putExtras(extras)
            }
        }
        return PendingIntent.getBroadcast(context, reqCode, intent, pendingFlags())
    }

    /**
     * Builds a `PendingIntent.getActivity` to `LifeOsWidgetQuickOverlayActivity`, a tiny translucent
     * floating popup over the Home Screen wallpaper (never launching full `MainActivity`).
     */
    fun buildOverlayPendingIntent(
        context: Context,
        overlayMode: String,
        reqCode: Int
    ): PendingIntent {
        val intent = Intent(context, LifeOsWidgetQuickOverlayActivity::class.java).apply {
            action = "vn.lifeos.app.WIDGET_OVERLAY_$overlayMode"
            data = Uri.parse("lifeos://widget_overlay/$overlayMode/$reqCode")
            putExtra("overlay_mode", overlayMode)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        }
        return PendingIntent.getActivity(context, reqCode, intent, pendingFlags())
    }

    /**
     * Bound ONLY to the small corner brand mark in case the user explicitly wants to open the app.
     */
    fun buildOpenAppPendingIntent(context: Context, action: String, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(context, reqCode, intent, pendingFlags())
    }

    fun formatVnd(amountMinor: Long, masked: Boolean = false, signPrefix: String = ""): String {
        if (masked) {
            return "${signPrefix}•••••••• ₫"
        }
        val isNeg = amountMinor < 0L
        val absVal = abs(amountMinor)
        val grouped = NumberFormat.getIntegerInstance(Locale.GERMANY).format(absVal)
        val effectiveSign = when {
            signPrefix.isNotEmpty() -> signPrefix
            isNeg -> "-"
            else -> ""
        }
        return "$effectiveSign$grouped ₫"
    }

    fun parseVietnameseAmountMinor(rawInput: String): Long {
        val text = rawInput.trim().lowercase(Locale.ROOT)
        if (text.isEmpty()) return 0L

        val millionRegex = Regex("""(\d+(?:[.,]\d+)?)\s*(?:tr|triệu|trieu|củ|cu)(?:\s*(\d{1,3}))?\b""")
        val mMatch = millionRegex.find(text)
        if (mMatch != null) {
            val base = mMatch.groupValues[1].replace(',', '.').toDoubleOrNull() ?: 0.0
            var total = (base * 1_000_000.0).roundToLong()
            val tail = mMatch.groupValues.getOrNull(2).orEmpty()
            if (tail.isNotEmpty()) {
                val scale = when (tail.length) {
                    1 -> 100_000L
                    2 -> 10_000L
                    else -> 1_000L
                }
                total += (tail.toLongOrNull() ?: 0L) * scale
            }
            return total
        }

        val thousandRegex = Regex("""(\d+(?:[.,]\d+)?)\s*(?:k|nghìn|nghin|ngàn|ngan)(?:\s*(\d{1,2}))?\b""")
        val kMatch = thousandRegex.find(text)
        if (kMatch != null) {
            val base = kMatch.groupValues[1].replace(',', '.').toDoubleOrNull() ?: 0.0
            var total = (base * 1_000.0).roundToLong()
            val tail = kMatch.groupValues.getOrNull(2).orEmpty()
            if (tail.isNotEmpty()) {
                val scale = if (tail.length == 1) 100L else 10L
                total += (tail.toLongOrNull() ?: 0L) * scale
            }
            return total
        }

        val rawVndRegex = Regex("""\b(\d{1,3}(?:[.,]\d{3})+|\d{4,11})\s*(?:đ|d|vnd|vnđ)?\b""")
        val rMatch = rawVndRegex.find(text)
        if (rMatch != null) {
            val digits = rMatch.groupValues[1].replace(".", "").replace(",", "")
            return digits.toLongOrNull() ?: 0L
        }
        return 0L
    }

    fun extractSplitMemberCount(rawInput: String, fallback: Int): Int {
        val m = Regex("""chia(?:\s+đều|\s+deu)?(?:\s+cho)?\s+(\d{1,2})""").find(rawInput.lowercase(Locale.ROOT))
        val parsed = m?.groupValues?.getOrNull(1)?.toIntOrNull()
        return (parsed ?: fallback).coerceIn(2, 20)
    }

    private fun isIncomeText(rawInput: String): Boolean {
        val lower = rawInput.lowercase(Locale.ROOT)
        val cues = listOf("lương", "luong", "thưởng", "thuong", "thu nhập", "thu nhap", "nhận tiền", "hoàn tiền")
        return cues.any { lower.contains(it) }
    }

    fun recordTransactionFromHomeScreen(
        context: Context,
        label: String,
        amountMinor: Long,
        isIncome: Boolean = false,
        rawCommandOverride: String? = null
    ) {
        if (amountMinor <= 0L) return
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val prevNetWorth = prefs.getLong("net_worth_minor", 0L)
        val prevIncome = prefs.getLong("monthly_income_minor", 0L)
        val prevExpense = prefs.getLong("monthly_expense_minor", 0L)
        val prevToday = prefs.getLong("today_expense_minor", 0L)
        val prevSafe = prefs.getLong("safe_daily_minor", 500_000L)

        val nextNetWorth = if (isIncome) prevNetWorth + amountMinor else prevNetWorth - amountMinor
        val nextIncome = if (isIncome) prevIncome + amountMinor else prevIncome
        val nextExpense = if (isIncome) prevExpense else prevExpense + amountMinor
        val nextToday = if (isIncome) prevToday else prevToday + amountMinor
        val nextSafe = if (isIncome) prevSafe else (prevSafe - amountMinor).coerceAtLeast(0L)
        val dailyCap = (nextSafe + nextToday).coerceAtLeast(1L)
        val usedPct = ((nextToday * 100L) / dailyCap).toInt().coerceIn(4, 100)

        val cmdId = UUID.randomUUID().toString()
        val commandText = rawCommandOverride?.takeIf { it.isNotBlank() }
            ?: if (isIncome) {
                "Nhận tiền $label ${amountMinor}đ"
            } else {
                "$label ${amountMinor}đ"
            }

        val cmdJson = JSONObject().apply {
            put("id", cmdId)
            put("kind", if (isIncome) "income" else "expense")
            put("commandText", commandText)
            put("label", label)
            put("amountMinor", amountMinor)
            put("createdAtEpochMs", System.currentTimeMillis())
        }
        enqueueWidgetCommand(appCtx, cmdJson)

        val undoSnapshot = JSONObject().apply {
            put("id", cmdId)
            put("kind", if (isIncome) "income" else "expense")
            put("label", label)
            put("amountMinor", amountMinor)
        }

        prefs.edit()
            .putLong("net_worth_minor", nextNetWorth)
            .putLong("monthly_income_minor", nextIncome)
            .putLong("monthly_expense_minor", nextExpense)
            .putLong("today_expense_minor", nextToday)
            .putLong("safe_daily_minor", nextSafe)
            .putString("net_worth_formatted", formatVnd(nextNetWorth))
            .putString("monthly_income_formatted", formatVnd(nextIncome, signPrefix = "+"))
            .putString("monthly_expense_formatted", formatVnd(nextExpense, signPrefix = "-"))
            .putString("today_expense_formatted", formatVnd(nextToday))
            .putString("safe_daily_formatted", formatVnd(nextSafe))
            .putInt("daily_used_pct", usedPct)
            .putString("voice_last_feedback", "Đã ghi: $label (${formatVnd(amountMinor)})")
            .putString(KEY_LAST_UNDOABLE_JSON, undoSnapshot.toString())
            .apply()

        refreshAllWidgets(appCtx)
        onBackgroundWidgetCommandPing?.invoke()
    }

    fun recordGroupSplitFromHomeScreen(
        context: Context,
        label: String,
        amountMinor: Long,
        memberCountOverride: Int? = null,
        rawCommandOverride: String? = null
    ) {
        if (amountMinor <= 0L) return
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val members = (memberCountOverride ?: prefs.getInt("group_member_count", 3)).coerceIn(2, 20)
        val perPerson = amountMinor / members

        val cmdId = UUID.randomUUID().toString()
        val commandText = rawCommandOverride?.takeIf { it.isNotBlank() }
            ?: "$label ${amountMinor}đ chia đều $members người"

        val cmdJson = JSONObject().apply {
            put("id", cmdId)
            put("kind", "group_split")
            put("commandText", commandText)
            put("label", label)
            put("amountMinor", amountMinor)
            put("memberCount", members)
            put("createdAtEpochMs", System.currentTimeMillis())
        }
        enqueueWidgetCommand(appCtx, cmdJson)

        val prevStatus = prefs.getString("group_status", "Chọn số người rồi chạm mức chia nhanh bên dưới")
            ?: "Chọn số người rồi chạm mức chia nhanh bên dưới"
        val undoSnapshot = JSONObject().apply {
            put("id", cmdId)
            put("kind", "group_split")
            put("label", label)
            put("amountMinor", amountMinor)
            put("prevGroupStatus", prevStatus)
        }

        val statusLine = "Đã chia $label: ${formatVnd(perPerson)}/người ($members người)"
        prefs.edit()
            .putInt("group_member_count", members)
            .putString("group_status", statusLine)
            .putString("voice_last_feedback", statusLine)
            .putString(KEY_LAST_UNDOABLE_JSON, undoSnapshot.toString())
            .apply()

        refreshAllWidgets(appCtx)
        onBackgroundWidgetCommandPing?.invoke()
    }

    fun undoLastHomeScreenCommand(context: Context): Boolean {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val rawUndo = prefs.getString(KEY_LAST_UNDOABLE_JSON, null)
        if (rawUndo.isNullOrBlank()) {
            prefs.edit()
                .putString("voice_last_feedback", "Chưa có thao tác mới nào để hoàn tác")
                .apply()
            refreshAllWidgets(appCtx)
            return false
        }

        return try {
            val snap = JSONObject(rawUndo)
            val targetId = snap.optString("id", "")
            val kind = snap.optString("kind", "expense")
            val label = snap.optString("label", "Giao dịch")
            val amount = snap.optLong("amountMinor", 0L)

            val removedBeforeSync = removeQueuedCommandById(appCtx, targetId)
            if (!removedBeforeSync && targetId.isNotEmpty()) {
                // Already synced live to Flutter -> enqueue compensating undo command
                enqueueWidgetCommand(
                    appCtx,
                    JSONObject().apply {
                        put("id", UUID.randomUUID().toString())
                        put("kind", "undo")
                        put("targetCommandId", targetId)
                        put("commandText", "")
                        put("label", label)
                        put("amountMinor", amount)
                        put("createdAtEpochMs", System.currentTimeMillis())
                    }
                )
            }

            val editor = prefs.edit().remove(KEY_LAST_UNDOABLE_JSON)
            if (kind == "expense" || kind == "income") {
                val isInc = kind == "income"
                val nextNet = if (isInc) {
                    prefs.getLong("net_worth_minor", 0L) - amount
                } else {
                    prefs.getLong("net_worth_minor", 0L) + amount
                }
                val nextInc = if (isInc) {
                    (prefs.getLong("monthly_income_minor", 0L) - amount).coerceAtLeast(0L)
                } else {
                    prefs.getLong("monthly_income_minor", 0L)
                }
                val nextExp = if (isInc) {
                    prefs.getLong("monthly_expense_minor", 0L)
                } else {
                    (prefs.getLong("monthly_expense_minor", 0L) - amount).coerceAtLeast(0L)
                }
                val nextToday = if (isInc) {
                    prefs.getLong("today_expense_minor", 0L)
                } else {
                    (prefs.getLong("today_expense_minor", 0L) - amount).coerceAtLeast(0L)
                }
                val nextSafe = if (isInc) {
                    prefs.getLong("safe_daily_minor", 0L)
                } else {
                    prefs.getLong("safe_daily_minor", 0L) + amount
                }
                val cap = (nextSafe + nextToday).coerceAtLeast(1L)
                val pct = ((nextToday * 100L) / cap).toInt().coerceIn(4, 100)

                editor
                    .putLong("net_worth_minor", nextNet)
                    .putLong("monthly_income_minor", nextInc)
                    .putLong("monthly_expense_minor", nextExp)
                    .putLong("today_expense_minor", nextToday)
                    .putLong("safe_daily_minor", nextSafe)
                    .putString("net_worth_formatted", formatVnd(nextNet))
                    .putString("monthly_income_formatted", formatVnd(nextInc, signPrefix = "+"))
                    .putString("monthly_expense_formatted", formatVnd(nextExp, signPrefix = "-"))
                    .putString("today_expense_formatted", formatVnd(nextToday))
                    .putString("safe_daily_formatted", formatVnd(nextSafe))
                    .putInt("daily_used_pct", pct)
            } else if (kind == "group_split") {
                val prevGroupStatus = snap.optString(
                    "prevGroupStatus",
                    "Chọn số người rồi chạm mức chia nhanh bên dưới"
                )
                editor.putString("group_status", prevGroupStatus)
            }
            editor.putString("voice_last_feedback", "Đã hoàn tác: $label")
            editor.apply()

            refreshAllWidgets(appCtx)
            onBackgroundWidgetCommandPing?.invoke()
            true
        } catch (_: Exception) {
            false
        }
    }

    fun recordQuickWaterFromHomeScreen(context: Context, addedMl: Int) {
        if (addedMl <= 0) return
        val appCtx = context.applicationContext
        val hPrefs = appCtx.getSharedPreferences(
            LifeOsAlarmScheduler.PREFS_HYDRATION_DAEMON,
            Context.MODE_PRIVATE
        )
        val today = LifeOsAlarmScheduler.todayDayKey()
        val savedDay = hPrefs.getString("dayKey", today) ?: today
        val prevWater = if (savedDay == today) hPrefs.getInt("waterMl", 0) else 0
        val targetMl = hPrefs.getInt("targetWaterMl", 2000).coerceAtLeast(500)
        val nextWater = (prevWater + addedMl).coerceAtMost(10_000)

        hPrefs.edit()
            .putString("dayKey", today)
            .putInt("waterMl", nextWater)
            .apply()

        // Queue into unified background health queue so DailyLifeBloc syncs cleanly without duplication
        LifeOsAlarmScheduler.enqueueBackgroundHealthAction(
            appCtx,
            JSONObject().apply {
                put("type", "water_logged")
                put("ml", addedMl)
                put("loggedAtEpochMs", System.currentTimeMillis())
            }
        )
        LifeOsAlarmScheduler.onBackgroundHealthActionPing?.invoke()

        appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt("safe_widget_mode", 1)
            .putString("voice_last_feedback", "Đã ghi uống +$addedMl ml ($nextWater/$targetMl ml)")
            .apply()

        refreshAllWidgets(appCtx)
    }

    fun handleFreeformHomeScreenInput(context: Context, rawText: String, mode: String): String {
        val cleaned = rawText.trim()
        if (cleaned.isEmpty()) return ""
        val appCtx = context.applicationContext
        val lower = cleaned.lowercase(Locale.ROOT)

        // Check water expression first (e.g. "Uống 300ml nước")
        val waterMatch = Regex("""(\d{2,4})\s*ml""").find(lower)
        if (waterMatch != null && (lower.contains("nước") || lower.contains("nuoc") || mode == "water")) {
            val ml = waterMatch.groupValues[1].toIntOrNull() ?: 250
            recordQuickWaterFromHomeScreen(appCtx, ml)
            return "Đã ghi uống +$ml ml nước"
        }

        val amount = parseVietnameseAmountMinor(cleaned)
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val defaultMembers = prefs.getInt("group_member_count", 3).coerceIn(2, 20)

        if (mode == "voice_split" || lower.contains("chia ")) {
            val splitAmount = if (amount > 0L) amount else 150_000L
            val members = extractSplitMemberCount(cleaned, defaultMembers)
            val titleLabel = cleaned
                .replace(Regex("""chia.*""", RegexOption.IGNORE_CASE), "")
                .trim()
                .ifEmpty { "Khoản chung" }
            recordGroupSplitFromHomeScreen(
                context = appCtx,
                label = titleLabel,
                amountMinor = splitAmount,
                memberCountOverride = members,
                rawCommandOverride = if (lower.contains("chia")) cleaned else "$cleaned chia đều $members người"
            )
            return "Đã chia ${formatVnd(splitAmount / members)}/người ($members người)"
        }

        if (amount > 0L) {
            val income = mode == "income" || isIncomeText(cleaned)
            val shortLabel = cleaned
                .replace(Regex("""\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan|đ|d|vnd|vnđ)\b""", RegexOption.IGNORE_CASE), "")
                .trim()
                .ifEmpty { if (income) "Thu nhập" else "Chi tiêu nhanh" }
            recordTransactionFromHomeScreen(
                context = appCtx,
                label = shortLabel,
                amountMinor = amount,
                isIncome = income,
                rawCommandOverride = cleaned
            )
            return "Đã lưu $shortLabel: ${formatVnd(amount)}"
        }

        // Generic omni command (task, calendar, grocery, etc.) -> queue straight to SmartOmniIntentParser
        val cmdJson = JSONObject().apply {
            put("id", UUID.randomUUID().toString())
            put("kind", "omni_text")
            put("commandText", cleaned)
            put("label", cleaned)
            put("amountMinor", 0L)
            put("createdAtEpochMs", System.currentTimeMillis())
        }
        enqueueWidgetCommand(appCtx, cmdJson)
        prefs.edit()
            .putString("voice_last_feedback", "Đã ghi lệnh: $cleaned")
            .apply()
        refreshAllWidgets(appCtx)
        onBackgroundWidgetCommandPing?.invoke()
        return "Đã lưu: $cleaned"
    }

    private fun enqueueWidgetCommand(context: Context, item: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_QUEUED_COMMANDS_JSON, "[]") ?: "[]"
        val nextArr = JSONArray()
        try {
            val oldArr = JSONArray(raw)
            val start = (oldArr.length() - 49).coerceAtLeast(0)
            for (i in start until oldArr.length()) {
                nextArr.put(oldArr.get(i))
            }
        } catch (_: Exception) {
        }
        nextArr.put(item)
        prefs.edit().putString(KEY_QUEUED_COMMANDS_JSON, nextArr.toString()).apply()
    }

    private fun removeQueuedCommandById(context: Context, commandId: String): Boolean {
        if (commandId.isEmpty()) return false
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_QUEUED_COMMANDS_JSON, "[]") ?: "[]"
        var removed = false
        val filtered = JSONArray()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                if (obj.optString("id") == commandId) {
                    removed = true
                } else {
                    filtered.put(obj)
                }
            }
        } catch (_: Exception) {
        }
        if (removed) {
            prefs.edit().putString(KEY_QUEUED_COMMANDS_JSON, filtered.toString()).apply()
        }
        return removed
    }

    fun drainQueuedCommands(context: Context): List<Map<String, Any>> {
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_QUEUED_COMMANDS_JSON, "[]") ?: "[]"
        prefs.edit().putString(KEY_QUEUED_COMMANDS_JSON, "[]").apply()
        val out = mutableListOf<Map<String, Any>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
                        "id" to obj.optString("id", ""),
                        "kind" to obj.optString("kind", "expense"),
                        "commandText" to obj.optString("commandText", ""),
                        "label" to obj.optString("label", ""),
                        "amountMinor" to obj.optLong("amountMinor", 0L),
                        "memberCount" to obj.optInt("memberCount", 3),
                        "targetCommandId" to obj.optString("targetCommandId", ""),
                        "createdAtEpochMs" to obj.optLong("createdAtEpochMs", 0L)
                    )
                )
            }
        } catch (_: Exception) {
        }
        return out
    }

    fun onBackgroundBankSignalCaptured(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pending = prefs.getInt("pending_auto_signals", 0) + 1
        prefs.edit()
            .putInt("pending_auto_signals", pending)
            .putString("wealth_badge", "+$pending mới")
            .apply()
        refreshAllWidgets(context)
    }

    fun refreshAllWidgets(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)

        val voiceIds = mgr.getAppWidgetIds(ComponentName(context, VoiceQuickWidgetProvider::class.java))
        if (voiceIds.isNotEmpty()) {
            VoiceQuickWidgetProvider.render(context, mgr, voiceIds)
        }

        val wealthIds = mgr.getAppWidgetIds(ComponentName(context, WealthNetWorthWidgetProvider::class.java))
        if (wealthIds.isNotEmpty()) {
            WealthNetWorthWidgetProvider.render(context, mgr, wealthIds)
        }

        val groupIds = mgr.getAppWidgetIds(ComponentName(context, GroupSplitWidgetProvider::class.java))
        if (groupIds.isNotEmpty()) {
            GroupSplitWidgetProvider.render(context, mgr, groupIds)
        }

        val safeIds = mgr.getAppWidgetIds(ComponentName(context, DailySafeSpendWidgetProvider::class.java))
        if (safeIds.isNotEmpty()) {
            DailySafeSpendWidgetProvider.render(context, mgr, safeIds)
        }
    }
}

/**
 * Direct On-Home-Screen `BroadcastReceiver` handling all widget button/pill taps
 * without launching `MainActivity`!
 */
class LifeOsWidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val appCtx = context.applicationContext
        val prefs = appCtx.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)

        when (action) {
            LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE -> {
                val label = intent.getStringExtra("label") ?: "Chi tiêu nhanh"
                val amountMinor = intent.getLongExtra("amountMinor", 35_000L)
                LifeOsWidgetStore.recordTransactionFromHomeScreen(
                    context = appCtx,
                    label = label,
                    amountMinor = amountMinor,
                    isIncome = false
                )
            }
            LifeOsWidgetStore.ACTION_BG_UNDO_LAST -> {
                LifeOsWidgetStore.undoLastHomeScreenCommand(appCtx)
            }
            LifeOsWidgetStore.ACTION_BG_TOGGLE_MASK -> {
                val nextMask = !prefs.getBoolean("hide_balances", false)
                prefs.edit().putBoolean("hide_balances", nextMask).apply()
                LifeOsWidgetStore.refreshAllWidgets(appCtx)
            }
            LifeOsWidgetStore.ACTION_BG_CYCLE_WEALTH_MODE -> {
                val nextMode = (prefs.getInt("wealth_mode", 0) + 1) % 3
                prefs.edit().putInt("wealth_mode", nextMode).apply()
                LifeOsWidgetStore.refreshAllWidgets(appCtx)
            }
            LifeOsWidgetStore.ACTION_BG_GROUP_MEMBER_DELTA -> {
                val delta = intent.getIntExtra("delta", 1)
                val current = prefs.getInt("group_member_count", 3)
                val next = (current + delta).coerceIn(2, 20)
                prefs.edit()
                    .putInt("group_member_count", next)
                    .putString("group_status", "Chế độ chia đều $next người · Chạm mức bên dưới để chia ngay")
                    .apply()
                LifeOsWidgetStore.refreshAllWidgets(appCtx)
            }
            LifeOsWidgetStore.ACTION_BG_QUICK_GROUP_SPLIT -> {
                val label = intent.getStringExtra("label") ?: "Ăn chung"
                val amountMinor = intent.getLongExtra("amountMinor", 150_000L)
                LifeOsWidgetStore.recordGroupSplitFromHomeScreen(
                    context = appCtx,
                    label = label,
                    amountMinor = amountMinor
                )
            }
            LifeOsWidgetStore.ACTION_BG_TOGGLE_SAFE_MODE -> {
                val nextMode = if (prefs.getInt("safe_widget_mode", 0) == 0) 1 else 0
                prefs.edit().putInt("safe_widget_mode", nextMode).apply()
                LifeOsWidgetStore.refreshAllWidgets(appCtx)
            }
            LifeOsWidgetStore.ACTION_BG_QUICK_WATER -> {
                val ml = intent.getIntExtra("waterMl", 250)
                LifeOsWidgetStore.recordQuickWaterFromHomeScreen(appCtx, ml)
            }
        }
    }
}

/**
 * Lightweight Translucent Floating Micro-Popup over the Android Home Screen Wallpaper.
 * Captures Vietnamese speech or quick freeform text and updates widgets right on the Home Screen
 * without ever opening `MainActivity` or spinning up a full-screen app!
 */
class LifeOsWidgetQuickOverlayActivity : Activity() {
    companion object {
        private const val REQ_SYSTEM_VOICE = 8811
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private lateinit var inputField: EditText
    private lateinit var statusLabel: TextView
    private var overlayMode: String = "text"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
        overlayMode = intent?.getStringExtra("overlay_mode") ?: "text"

        val isDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

        val cardBg = if (isDark) Color.parseColor("#191C1A") else Color.parseColor("#FFFFFF")
        val boxBg = if (isDark) Color.parseColor("#232A26") else Color.parseColor("#F1F8F3")
        val chipBg = if (isDark) Color.parseColor("#183925") else Color.parseColor("#DCFCE7")
        val chipFg = if (isDark) Color.parseColor("#86EFAC") else Color.parseColor("#0F5132")
        val primaryBg = if (isDark) Color.parseColor("#22C55E") else Color.parseColor("#12B847")
        val onPrimary = if (isDark) Color.parseColor("#052E16") else Color.parseColor("#FFFFFF")
        val textPrimary = if (isDark) Color.parseColor("#F1F5F9") else Color.parseColor("#101828")
        val textSecondary = if (isDark) Color.parseColor("#94A3B8") else Color.parseColor("#475467")
        val strokeColor = if (isDark) Color.parseColor("#2C3731") else Color.parseColor("#E4E7EC")

        val backdrop = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(dp(16), dp(56), dp(16), dp(24))
            setOnClickListener { closeQuietly() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setPadding(dp(18), dp(16), dp(18), dp(16))
            background = roundedShape(cardBg, dpF(28f), strokeColor, dp(1))
            elevation = dpF(16f)
        }
        val cardLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        }

        // Header Row
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val headerTitle = TextView(this).apply {
            text = when (overlayMode) {
                "voice_split" -> "Chia tiền nhóm ngay trên màn hình"
                "income" -> "Ghi thu nhập nhanh trên Widget"
                "voice" -> "Nói ghi nhanh ngay trên màn hình"
                else -> "Ghi nhanh trực tiếp trên Widget"
            }
            setTextColor(textPrimary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val closeBtn = TextView(this).apply {
            text = "Đóng"
            setTextColor(textSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = roundedShape(boxBg, dpF(16f))
            setOnClickListener { closeQuietly() }
        }
        headerRow.addView(headerTitle)
        headerRow.addView(closeBtn)
        card.addView(headerRow)

        statusLabel = TextView(this).apply {
            text = "Gõ hoặc bấm Nói mic — lưu xong sẽ ở nguyên màn hình chính"
            setTextColor(textSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, dp(4), 0, dp(8))
        }
        card.addView(statusLabel)

        // Input Box
        inputField = EditText(this).apply {
            hint = when (overlayMode) {
                "voice_split" -> "VD: Ăn lẩu 450k chia 3 người"
                "income" -> "VD: Nhận thưởng 2tr5, Lương 18tr"
                else -> "VD: Phở bò 45k, Đổ xăng 70k, Uống 300ml nước"
            }
            setHintTextColor(textSecondary)
            setTextColor(textPrimary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = EditorInfo.IME_ACTION_DONE
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedShape(boxBg, dpF(18f), strokeColor, dp(1))
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_DONE) {
                    commitAndFinish()
                    true
                } else {
                    false
                }
            }
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    val raw = s?.toString().orEmpty().trim()
                    if (raw.isEmpty()) return
                    val amt = LifeOsWidgetStore.parseVietnameseAmountMinor(raw)
                    if (amt > 0L) {
                        statusLabel.text = "Nhận diện số tiền: ${LifeOsWidgetStore.formatVnd(amt)}"
                    }
                }
            })
        }
        card.addView(inputField)

        // Quick Preset Chips inside Overlay
        val presetsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(10), 0, dp(12))
        }
        val presets = when (overlayMode) {
            "voice_split" -> listOf("Ăn trưa 240k chia 3", "Tiền điện 900k chia 3")
            "income" -> listOf("Thưởng 1tr5", "Hoàn tiền 150k")
            else -> listOf("Phở 45k", "Trà sữa 40k", "Siêu thị 150k")
        }
        presets.forEachIndexed { index, sample ->
            val chip = TextView(this).apply {
                text = sample
                setTextColor(chipFg)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                setTypeface(typeface, Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(dp(10), dp(7), dp(10), dp(7))
                background = roundedShape(chipBg, dpF(16f))
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    if (index > 0) leftMargin = dp(6)
                }
                setOnClickListener {
                    inputField.setText(sample)
                    inputField.setSelection(sample.length)
                    commitAndFinish()
                }
            }
            presetsRow.addView(chip)
        }
        card.addView(presetsRow)

        // Action Row: Nói mic + Lưu lên Widget
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val micBtn = TextView(this).apply {
            text = "Nói mic tiếng Việt"
            setTextColor(chipFg)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(11), dp(12), dp(11))
            background = roundedShape(chipBg, dpF(20f))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setOnClickListener { startVoiceListening() }
        }
        val saveBtn = TextView(this).apply {
            text = "Lưu lên Widget"
            setTextColor(onPrimary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(11), dp(14), dp(11))
            background = roundedShape(primaryBg, dpF(20f))
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.15f).apply {
                leftMargin = dp(8)
            }
            setOnClickListener { commitAndFinish() }
        }
        actionsRow.addView(micBtn)
        actionsRow.addView(saveBtn)
        card.addView(actionsRow)

        backdrop.addView(card, cardLp)
        setContentView(backdrop)

        if (overlayMode == "voice" || overlayMode == "voice_split") {
            startVoiceListening()
        } else {
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            inputField.requestFocus()
        }
    }

    private fun startVoiceListening() {
        val recIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 2)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Nói chi tiêu hoặc khoản chia nhóm...")
        }

        val hasAudioPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (hasAudioPerm && SpeechRecognizer.isRecognitionAvailable(this)) {
            try {
                speechRecognizer?.destroy()
                val sr = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer = sr
                statusLabel.text = "Đang nghe giọng nói tiếng Việt..."
                var lastPartial = ""
                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        statusLabel.text = "Mời bạn nói (VD: Cà phê 35 nghìn)..."
                    }
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {
                        statusLabel.text = "Đang xử lý câu nói..."
                    }
                    override fun onPartialResults(partialResults: Bundle?) {
                        val txt = partialResults
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            .orEmpty()
                        if (txt.isNotBlank()) {
                            lastPartial = txt
                            inputField.setText(txt)
                            inputField.setSelection(txt.length)
                        }
                    }
                    override fun onResults(results: Bundle?) {
                        val txt = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.takeIf { it.isNotBlank() }
                            ?: lastPartial
                        if (txt.isNotBlank()) {
                            inputField.setText(txt)
                            inputField.setSelection(txt.length)
                            statusLabel.text = "Đã nghe rõ — bấm Lưu lên Widget để hoàn tất"
                        }
                    }
                    override fun onError(error: Int) {
                        if (lastPartial.isNotBlank()) {
                            inputField.setText(lastPartial)
                            inputField.setSelection(lastPartial.length)
                            statusLabel.text = "Đã ghi nhận câu nói — kiểm tra rồi bấm Lưu"
                        } else {
                            statusLabel.text = "Chưa nghe rõ — hãy thử nói lại hoặc gõ trực tiếp"
                        }
                    }
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
                sr.startListening(recIntent)
                return
            } catch (_: Exception) {
            }
        }

        // Fallback to Android System Speech Dialog (works even without RECORD_AUDIO permission!)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(recIntent, REQ_SYSTEM_VOICE)
        } catch (_: Exception) {
            statusLabel.text = "Hãy gõ nội dung cần ghi nhanh bên dưới"
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            inputField.requestFocus()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SYSTEM_VOICE && resultCode == RESULT_OK) {
            val spoken = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
                .orEmpty()
            if (spoken.isNotBlank()) {
                inputField.setText(spoken)
                inputField.setSelection(spoken.length)
                commitAndFinish()
            }
        }
    }

    private fun commitAndFinish() {
        val raw = inputField.text?.toString().orEmpty().trim()
        if (raw.isEmpty()) {
            statusLabel.text = "Vui lòng nhập hoặc nói nội dung trước khi lưu"
            return
        }
        val summary = LifeOsWidgetStore.handleFreeformHomeScreenInput(
            context = applicationContext,
            rawText = raw,
            mode = overlayMode
        )
        if (summary.isNotEmpty()) {
            Toast.makeText(applicationContext, summary, Toast.LENGTH_SHORT).show()
        }
        closeQuietly()
    }

    private fun closeQuietly() {
        finish()
        overridePendingTransition(0, 0)
    }

    override fun onDestroy() {
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()

    private fun dpF(value: Float): Float =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            resources.displayMetrics
        )

    private fun roundedShape(
        fillColor: Int,
        radiusPx: Float,
        strokeColor: Int = Color.TRANSPARENT,
        strokeWidthPx: Int = 0
    ): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radiusPx
        setColor(fillColor)
        if (strokeWidthPx > 0) {
            setStroke(strokeWidthPx, strokeColor)
        }
    }
}

/**
 * Widget 1: Interactive On-Home-Screen Voice & 1-Tap Expense Quick Bar (4x2 Material 3)
 */
class VoiceQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val masked = prefs.getBoolean("hide_balances", false)
            val todayMinor = prefs.getLong("today_expense_minor", -1L)
            val todaySpend = if (todayMinor >= 0L) {
                LifeOsWidgetStore.formatVnd(todayMinor, masked = masked)
            } else if (masked) {
                "•••••••• ₫"
            } else {
                prefs.getString("today_expense_formatted", "0 ₫") ?: "0 ₫"
            }
            val hint = prefs.getString(
                "voice_last_feedback",
                "Chạm nói, gõ nhanh hoặc bấm mức bên dưới"
            ) ?: "Chạm nói, gõ nhanh hoặc bấm mức bên dưới"

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_voice_quick)
                views.setTextViewText(R.id.tv_voice_hint, hint)
                views.setTextViewText(R.id.tv_voice_today_spend, "Chi hôm nay: $todaySpend")

                // Floating Home-Screen overlays (never opens MainActivity!)
                views.setOnClickPendingIntent(
                    R.id.box_voice_prompt,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "text", 100)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_voice_mic,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "voice", 101)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_voice_split,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "voice_split", 102)
                )

                // Direct 1-Tap Broadcast buttons right on the Home Screen (0 Activity launch!)
                views.setOnClickPendingIntent(
                    R.id.btn_voice_chip_35k,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE,
                        111,
                        Bundle().apply {
                            putString("label", "Cà phê")
                            putLong("amountMinor", 35_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_voice_chip_50k,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE,
                        112,
                        Bundle().apply {
                            putString("label", "Ăn uống")
                            putLong("amountMinor", 50_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_voice_chip_80k,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE,
                        113,
                        Bundle().apply {
                            putString("label", "Đổ xăng")
                            putLong("amountMinor", 80_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_voice_undo,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_UNDO_LAST,
                        114
                    )
                )

                // Optional explicit app open ONLY on small leaf logo
                views.setOnClickPendingIntent(
                    R.id.img_voice_open_app,
                    LifeOsWidgetStore.buildOpenAppPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_TODAY, 199)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 2: Interactive On-Home-Screen Net Worth & Cashflow Card (4x2 Material 3)
 */
class WealthNetWorthWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val masked = prefs.getBoolean("hide_balances", false)
            val wealthMode = prefs.getInt("wealth_mode", 0).coerceIn(0, 2)

            val hasMinor = prefs.contains("net_worth_minor")
            val netWorthMinor = prefs.getLong("net_worth_minor", 0L)
            val incomeMinor = prefs.getLong("monthly_income_minor", 0L)
            val expenseMinor = prefs.getLong("monthly_expense_minor", 0L)
            val todayMinor = prefs.getLong("today_expense_minor", 0L)

            val (modeTitle, headlineText) = when (wealthMode) {
                1 -> {
                    val monthlySurplus = incomeMinor - expenseMinor
                    val prefix = if (monthlySurplus > 0L) "+" else ""
                    "Dư ròng tháng này" to LifeOsWidgetStore.formatVnd(
                        monthlySurplus,
                        masked = masked,
                        signPrefix = prefix
                    )
                }
                2 -> {
                    "Đã chi tiêu hôm nay" to LifeOsWidgetStore.formatVnd(
                        todayMinor,
                        masked = masked
                    )
                }
                else -> {
                    val nw = if (hasMinor) {
                        LifeOsWidgetStore.formatVnd(netWorthMinor, masked = masked)
                    } else if (masked) {
                        "•••••••• ₫"
                    } else {
                        prefs.getString("net_worth_formatted", "0 ₫") ?: "0 ₫"
                    }
                    "Tổng tài sản ròng" to nw
                }
            }

            val incomeText = if (hasMinor) {
                LifeOsWidgetStore.formatVnd(incomeMinor, masked = masked, signPrefix = "+")
            } else if (masked) {
                "+•••••••• ₫"
            } else {
                prefs.getString("monthly_income_formatted", "+0 ₫") ?: "+0 ₫"
            }

            val expenseText = if (hasMinor) {
                LifeOsWidgetStore.formatVnd(expenseMinor, masked = masked, signPrefix = "-")
            } else if (masked) {
                "-•••••••• ₫"
            } else {
                prefs.getString("monthly_expense_formatted", "-0 ₫") ?: "-0 ₫"
            }

            val pendingAuto = prefs.getInt("pending_auto_signals", 0)
            val badge = if (pendingAuto > 0) {
                "+$pendingAuto mới"
            } else {
                when (wealthMode) {
                    1 -> "Góc nhìn 2/3"
                    2 -> "Góc nhìn 3/3"
                    else -> "Đổi góc nhìn"
                }
            }

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_wealth_net_worth)
                views.setTextViewText(R.id.tv_wealth_mode_title, modeTitle)
                views.setTextViewText(R.id.tv_wealth_net_worth, headlineText)
                views.setTextViewText(R.id.tv_wealth_income, incomeText)
                views.setTextViewText(R.id.tv_wealth_expense, expenseText)
                views.setTextViewText(R.id.tv_wealth_badge, badge)
                views.setTextViewText(
                    R.id.btn_wealth_toggle_mask,
                    if (masked) "Hiện số" else "Ẩn số"
                )

                // Direct Broadcast actions right on Home Screen (Privacy mask + Mode cycle)
                views.setOnClickPendingIntent(
                    R.id.btn_wealth_toggle_mask,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_TOGGLE_MASK,
                        211
                    )
                )
                val cyclePi = LifeOsWidgetStore.buildBroadcastPendingIntent(
                    context,
                    LifeOsWidgetStore.ACTION_BG_CYCLE_WEALTH_MODE,
                    212
                )
                views.setOnClickPendingIntent(R.id.tv_wealth_badge, cyclePi)
                views.setOnClickPendingIntent(R.id.tv_wealth_net_worth, cyclePi)

                // Floating quick-entry overlays over wallpaper (never opens MainActivity!)
                views.setOnClickPendingIntent(
                    R.id.btn_wealth_quick_add,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "text", 221)
                )
                views.setOnClickPendingIntent(
                    R.id.box_wealth_income,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "income", 222)
                )
                views.setOnClickPendingIntent(
                    R.id.box_wealth_expense,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "text", 223)
                )

                // Optional explicit app open ONLY on small leaf logo
                views.setOnClickPendingIntent(
                    R.id.img_wealth_open_app,
                    LifeOsWidgetStore.buildOpenAppPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FINANCE, 299)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 3: Interactive On-Home-Screen Family & Roommates Split Hub (4x2 Material 3)
 */
class GroupSplitWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val groupTitle = prefs.getString("group_title", "Tổ ấm & Hội nhóm")
                ?: "Tổ ấm & Hội nhóm"
            val members = prefs.getInt("group_member_count", 3).coerceIn(2, 20)
            val groupStatus = prefs.getString(
                "group_status",
                "Chọn số người rồi chạm mức chia nhanh bên dưới"
            ) ?: "Chọn số người rồi chạm mức chia nhanh bên dưới"

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_group_split)
                views.setTextViewText(R.id.tv_group_name, groupTitle)
                views.setTextViewText(R.id.tv_group_members, "$members người")
                views.setTextViewText(R.id.tv_group_status, groupStatus)

                // Direct Broadcast Member Stepper (- / +) right on Home Screen
                views.setOnClickPendingIntent(
                    R.id.btn_group_minus,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_GROUP_MEMBER_DELTA,
                        311,
                        Bundle().apply { putInt("delta", -1) }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_group_plus,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_GROUP_MEMBER_DELTA,
                        312,
                        Bundle().apply { putInt("delta", 1) }
                    )
                )

                // Direct Broadcast 1-Tap Equal Splits right on Home Screen
                views.setOnClickPendingIntent(
                    R.id.btn_group_split_150k,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_GROUP_SPLIT,
                        313,
                        Bundle().apply {
                            putString("label", "Ăn chung")
                            putLong("amountMinor", 150_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_group_split_300k,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_GROUP_SPLIT,
                        314,
                        Bundle().apply {
                            putString("label", "Hóa đơn chung")
                            putLong("amountMinor", 300_000L)
                        }
                    )
                )

                // Floating Voice Split overlay over Home Screen wallpaper
                views.setOnClickPendingIntent(
                    R.id.btn_group_voice_split,
                    LifeOsWidgetStore.buildOverlayPendingIntent(context, "voice_split", 321)
                )

                // Optional explicit app open ONLY on small leaf logo
                views.setOnClickPendingIntent(
                    R.id.img_group_open_app,
                    LifeOsWidgetStore.buildOpenAppPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FAMILY, 399)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 4: Interactive On-Home-Screen Daily Safe-to-Spend & Hydration +250ml Card (3x2 Material 3)
 */
class DailySafeSpendWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val safeMode = prefs.getInt("safe_widget_mode", 0) // 0 = Safe Spend, 1 = Hydration
            val masked = prefs.getBoolean("hide_balances", false)

            val toggleModePi = LifeOsWidgetStore.buildBroadcastPendingIntent(
                context,
                LifeOsWidgetStore.ACTION_BG_TOGGLE_SAFE_MODE,
                410
            )

            if (safeMode == 1) {
                val hPrefs = context.getSharedPreferences(
                    LifeOsAlarmScheduler.PREFS_HYDRATION_DAEMON,
                    Context.MODE_PRIVATE
                )
                val today = LifeOsAlarmScheduler.todayDayKey()
                val savedDay = hPrefs.getString("dayKey", today) ?: today
                val waterMl = if (savedDay == today) hPrefs.getInt("waterMl", 0) else 0
                val targetMl = hPrefs.getInt("targetWaterMl", 2000).coerceAtLeast(500)
                val waterPct = ((waterMl * 100) / targetMl).coerceIn(4, 100)
                val remainMl = (targetMl - waterMl).coerceAtLeast(0)
                val subText = if (remainMl == 0) {
                    "Đã hoàn thành mục tiêu nước hôm nay!"
                } else {
                    "Còn $remainMl ml để đủ chuẩn $targetMl ml"
                }

                for (id in ids) {
                    val views = RemoteViews(context.packageName, R.layout.widget_daily_safe_spend)
                    views.setTextViewText(R.id.tv_safe_mode_title, "Nước uống hôm nay")
                    views.setTextViewText(R.id.tv_safe_pct_badge, "$waterPct% · Đổi")
                    views.setTextViewText(R.id.tv_safe_daily_amount, "$waterMl / $targetMl ml")
                    views.setProgressBar(R.id.pb_safe_daily, 100, waterPct, false)
                    views.setTextViewText(R.id.tv_safe_runway, subText)
                    views.setTextViewText(R.id.btn_safe_action_1, "+250ml")
                    views.setTextViewText(R.id.btn_safe_action_2, "+350ml")
                    views.setTextViewText(R.id.btn_safe_switch_mode, "Hạn mức")

                    views.setOnClickPendingIntent(R.id.tv_safe_pct_badge, toggleModePi)
                    views.setOnClickPendingIntent(R.id.btn_safe_switch_mode, toggleModePi)
                    views.setOnClickPendingIntent(
                        R.id.btn_safe_action_1,
                        LifeOsWidgetStore.buildBroadcastPendingIntent(
                            context,
                            LifeOsWidgetStore.ACTION_BG_QUICK_WATER,
                            421,
                            Bundle().apply { putInt("waterMl", 250) }
                        )
                    )
                    views.setOnClickPendingIntent(
                        R.id.btn_safe_action_2,
                        LifeOsWidgetStore.buildBroadcastPendingIntent(
                            context,
                            LifeOsWidgetStore.ACTION_BG_QUICK_WATER,
                            422,
                            Bundle().apply { putInt("waterMl", 350) }
                        )
                    )
                    views.setOnClickPendingIntent(
                        R.id.img_safe_open_app,
                        LifeOsWidgetStore.buildOpenAppPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_TODAY, 499)
                    )
                    mgr.updateAppWidget(id, views)
                }
                return
            }

            // Mode 0: Daily Safe-to-Spend with direct -20k / -50k Broadcast buttons
            val hasMinor = prefs.contains("safe_daily_minor")
            val safeDaily = if (hasMinor) {
                LifeOsWidgetStore.formatVnd(prefs.getLong("safe_daily_minor", 0L), masked = masked)
            } else if (masked) {
                "•••••••• ₫"
            } else {
                prefs.getString("safe_daily_formatted", "0 ₫") ?: "0 ₫"
            }
            val runwayLabel = prefs.getString("runway_label", "Quỹ dự phòng ổn định · Tự động cập nhật")
                ?: "Quỹ dự phòng ổn định · Tự động cập nhật"
            val usedPct = prefs.getInt("daily_used_pct", 15).coerceIn(4, 100)

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_daily_safe_spend)
                views.setTextViewText(R.id.tv_safe_mode_title, "Hạn mức hôm nay")
                views.setTextViewText(R.id.tv_safe_daily_amount, safeDaily)
                views.setTextViewText(R.id.tv_safe_runway, runwayLabel)
                views.setTextViewText(R.id.tv_safe_pct_badge, "Đã dùng $usedPct%")
                views.setProgressBar(R.id.pb_safe_daily, 100, usedPct, false)
                views.setTextViewText(R.id.btn_safe_action_1, "-20k Nhanh")
                views.setTextViewText(R.id.btn_safe_action_2, "-50k Ăn uống")
                views.setTextViewText(R.id.btn_safe_switch_mode, "Nước")

                views.setOnClickPendingIntent(R.id.tv_safe_pct_badge, toggleModePi)
                views.setOnClickPendingIntent(R.id.btn_safe_switch_mode, toggleModePi)
                views.setOnClickPendingIntent(
                    R.id.btn_safe_action_1,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE,
                        411,
                        Bundle().apply {
                            putString("label", "Chi vặt")
                            putLong("amountMinor", 20_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.btn_safe_action_2,
                    LifeOsWidgetStore.buildBroadcastPendingIntent(
                        context,
                        LifeOsWidgetStore.ACTION_BG_QUICK_EXPENSE,
                        412,
                        Bundle().apply {
                            putString("label", "Ăn uống")
                            putLong("amountMinor", 50_000L)
                        }
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.img_safe_open_app,
                    LifeOsWidgetStore.buildOpenAppPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FINANCE, 499)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}
