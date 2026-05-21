package com.saanjh.saanjh

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Saanjh home screen widget.
 *
 * Data is written by HomeWidgetService (Dart) via home_widget plugin's
 * SharedPreferences bridge, then read here on each widget update.
 *
 * Layout auto-selects between saanjh_widget (2×2) and saanjh_widget_wide (2×4)
 * based on the available widget width at update time.
 */
class SaanjhWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        val contactName = prefs.getString("contact_name", "—") ?: "—"
        val streakDays  = prefs.getInt("streak_days", 0)
        val pulseTime   = prefs.getString("pulse_time", "") ?: ""
        val wasHere     = prefs.getBoolean("was_here", false)

        val streakLabel = if (streakDays > 0) "🔥 $streakDays" else "🔥 —"
        val pulseLabel  = if (wasHere && pulseTime.isNotEmpty())
            "was here at $pulseTime"
        else if (wasHere) "was here today"
        else ""

        for (widgetId in appWidgetIds) {
            // Use wide layout for wide widgets (≥250dp), small layout otherwise.
            val options = appWidgetManager.getAppWidgetOptions(widgetId)
            val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
            val useWide  = maxWidth >= 250

            val layoutId = if (useWide) R.layout.saanjh_widget_wide else R.layout.saanjh_widget
            val views    = RemoteViews(context.packageName, layoutId)

            if (useWide) {
                views.setTextViewText(R.id.widget_wide_contact_name, contactName)
                views.setTextViewText(R.id.widget_wide_pulse_label, pulseLabel)
                views.setTextViewText(R.id.widget_wide_streak, streakLabel)
            } else {
                views.setTextViewText(R.id.widget_contact_name, contactName)
                views.setTextViewText(R.id.widget_pulse_label, pulseLabel)
                views.setTextViewText(R.id.widget_streak, streakLabel)
            }

            // Tap → open app (MainActivity).
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context, widgetId, launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(
                    if (useWide) R.id.widget_wide_cta else R.id.widget_contact_name,
                    pendingIntent
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
