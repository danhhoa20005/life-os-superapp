package vn.lifeos.app.life_os

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

object LifeOsWidgetStore {
    const val PREFS_NAME = "lifeos_home_widgets_prefs"

    const val ACTION_VOICE_CAPTURE = "vn.lifeos.app.WIDGET_ACTION_VOICE_CAPTURE"
    const val ACTION_VOICE_SPLIT = "vn.lifeos.app.WIDGET_ACTION_VOICE_SPLIT"
    const val ACTION_OPEN_TODAY = "vn.lifeos.app.WIDGET_ACTION_OPEN_TODAY"
    const val ACTION_OPEN_FINANCE = "vn.lifeos.app.WIDGET_ACTION_OPEN_FINANCE"
    const val ACTION_OPEN_FAMILY = "vn.lifeos.app.WIDGET_ACTION_OPEN_FAMILY"

    fun buildLaunchPendingIntent(context: Context, action: String, reqCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, reqCode, intent, piFlags)
    }

    fun onBackgroundBankSignalCaptured(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pending = prefs.getInt("pending_auto_signals", 0) + 1
        prefs.edit()
            .putInt("pending_auto_signals", pending)
            .putString("wealth_badge", "+$pending mới tự bắt")
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
 * Widget 1: Voice AI Quick Expense & Sentence Split Bar (4x2)
 */
class VoiceQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val todaySpend = prefs.getString("today_expense_formatted", "0 ₫") ?: "0 ₫"

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_voice_quick)
                views.setTextViewText(R.id.tv_voice_today_spend, "Hôm nay: $todaySpend")
                views.setOnClickPendingIntent(
                    R.id.btn_widget_voice_mic,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_VOICE_CAPTURE, 101)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_widget_voice_split,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_VOICE_SPLIT, 102)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_voice_root,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_VOICE_CAPTURE, 103)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 2: Executive Net Worth & Cashflow Private Banking Card (4x2)
 */
class WealthNetWorthWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val netWorth = prefs.getString("net_worth_formatted", "0 ₫") ?: "0 ₫"
            val income = prefs.getString("monthly_income_formatted", "+0 ₫") ?: "+0 ₫"
            val expense = prefs.getString("monthly_expense_formatted", "-0 ₫") ?: "-0 ₫"
            val badge = prefs.getString("wealth_badge", "Auto-Sync") ?: "Auto-Sync"

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_wealth_net_worth)
                views.setTextViewText(R.id.tv_wealth_net_worth, netWorth)
                views.setTextViewText(R.id.tv_wealth_income, "↓ Thu: $income")
                views.setTextViewText(R.id.tv_wealth_expense, "↑ Chi: $expense")
                views.setTextViewText(R.id.tv_wealth_badge, badge)
                views.setOnClickPendingIntent(
                    R.id.widget_wealth_root,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_TODAY, 201)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 3: Group, Roommates & Family Bill Split + VietQR Hub (4x2)
 */
class GroupSplitWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val groupTitle = prefs.getString("group_title", "HỘI NHÓM & GIA ĐÌNH · CHIA TIỀN NHANH")
                ?: "HỘI NHÓM & GIA ĐÌNH · CHIA TIỀN NHANH"
            val groupStatus = prefs.getString("group_status", "Nói câu chia ăn uống, việc nhà, điện nước")
                ?: "Nói câu chia ăn uống, việc nhà, điện nước"

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_group_split)
                views.setTextViewText(R.id.tv_group_name, groupTitle)
                views.setTextViewText(R.id.tv_group_status, groupStatus)
                views.setOnClickPendingIntent(
                    R.id.btn_group_voice_split,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_VOICE_SPLIT, 301)
                )
                views.setOnClickPendingIntent(
                    R.id.btn_group_vietqr,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FAMILY, 302)
                )
                views.setOnClickPendingIntent(
                    R.id.widget_group_root,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FAMILY, 303)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}

/**
 * Widget 4: Daily Safe-to-Spend & Emergency Runway Discipline Card (3x2)
 */
class DailySafeSpendWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(LifeOsWidgetStore.PREFS_NAME, Context.MODE_PRIVATE)
            val safeDaily = prefs.getString("safe_daily_formatted", "0 ₫") ?: "0 ₫"
            val runwayLabel = prefs.getString("runway_label", "Quỹ dự phòng ổn định · Tự động bắt số dư")
                ?: "Quỹ dự phòng ổn định · Tự động bắt số dư"
            val usedPct = prefs.getInt("daily_used_pct", 15).coerceIn(4, 100)

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_daily_safe_spend)
                views.setTextViewText(R.id.tv_safe_daily_amount, safeDaily)
                views.setTextViewText(R.id.tv_safe_runway, runwayLabel)
                views.setProgressBar(R.id.pb_safe_daily, 100, usedPct, false)
                views.setOnClickPendingIntent(
                    R.id.widget_safe_root,
                    LifeOsWidgetStore.buildLaunchPendingIntent(context, LifeOsWidgetStore.ACTION_OPEN_FINANCE, 401)
                )
                mgr.updateAppWidget(id, views)
            }
        }
    }
}
