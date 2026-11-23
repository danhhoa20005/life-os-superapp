package vn.lifeos.app.life_os

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import java.util.TimeZone

/**
 * Native Android System Calendar Bridge (`CalendarContract`) for real 2-way synchronization
 * with Google Calendar app, Samsung Calendar, Xiaomi/OPPO Calendar, Outlook, Exchange & CalDAV.
 */
object LifeOsDeviceCalendar {

    fun hasPermission(context: Context): Boolean {
        val readOk = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        val writeOk = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
        return readOk && writeOk
    }

    private fun colorIntToHex(colorInt: Int): String {
        if (colorInt == 0) return "#0B7A2A"
        val rgb = colorInt and 0x00FFFFFF
        return String.format("#%06X", rgb)
    }

    fun listCalendars(context: Context): List<Map<String, Any?>> {
        if (!hasPermission(context)) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.CALENDAR_TIME_ZONE
        )

        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndex(CalendarContract.Calendars._ID)
            val nameIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accNameIdx = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_NAME)
            val accTypeIdx = cursor.getColumnIndex(CalendarContract.Calendars.ACCOUNT_TYPE)
            val colorIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_COLOR)
            val primaryIdx = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
            val visIdx = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)
            val accessIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
            val tzIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_TIME_ZONE)

            while (cursor.moveToNext()) {
                val visible = if (visIdx >= 0) cursor.getInt(visIdx) else 1
                if (visible == 0) continue

                val id = if (idIdx >= 0) cursor.getLong(idIdx) else continue
                val displayName = if (nameIdx >= 0) cursor.getString(nameIdx).orEmpty() else ""
                val accountName = if (accNameIdx >= 0) cursor.getString(accNameIdx).orEmpty() else ""
                val accountType = if (accTypeIdx >= 0) cursor.getString(accTypeIdx).orEmpty() else ""
                val colorInt = if (colorIdx >= 0) cursor.getInt(colorIdx) else 0
                val isPrimaryFlag = if (primaryIdx >= 0 && !cursor.isNull(primaryIdx)) {
                    cursor.getInt(primaryIdx) == 1
                } else {
                    displayName.isNotBlank() && displayName.equals(accountName, ignoreCase = true)
                }
                val accessLevel = if (accessIdx >= 0) cursor.getInt(accessIdx) else 0
                val isReadOnly = accessLevel < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
                val tz = if (tzIdx >= 0) cursor.getString(tzIdx) else null

                val cleanSummary = when {
                    displayName.isNotBlank() -> displayName
                    accountName.isNotBlank() -> accountName
                    else -> "Lịch Thiết bị #$id"
                }

                results.add(
                    mapOf(
                        "deviceCalendarId" to id,
                        "summary" to cleanSummary,
                        "accountName" to accountName,
                        "accountType" to accountType,
                        "colorHex" to colorIntToHex(colorInt),
                        "isPrimary" to isPrimaryFlag,
                        "isReadOnly" to isReadOnly,
                        "timeZone" to (tz ?: TimeZone.getDefault().id)
                    )
                )
            }
        }
        return results
    }

    fun listEvents(
        context: Context,
        windowStartMs: Long,
        windowEndMs: Long
    ): List<Map<String, Any?>> {
        if (!hasPermission(context)) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()

        val builder: Uri.Builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, windowStartMs)
        ContentUris.appendId(builder, windowEndMs)

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Events.EVENT_TIMEZONE,
            CalendarContract.Instances.DISPLAY_COLOR,
            CalendarContract.Events.RRULE,
            CalendarContract.Events._SYNC_ID,
            CalendarContract.Events.STATUS,
            CalendarContract.Events.VISIBLE
        )

        val sortOrder = "${CalendarContract.Instances.BEGIN} ASC"
        val seenKeys = HashSet<String>()

        context.contentResolver.query(
            builder.build(),
            projection,
            null,
            null,
            sortOrder
        )?.use { cursor ->
            val evIdIdx = cursor.getColumnIndex(CalendarContract.Instances.EVENT_ID)
            val calIdIdx = cursor.getColumnIndex(CalendarContract.Events.CALENDAR_ID)
            val titleIdx = cursor.getColumnIndex(CalendarContract.Instances.TITLE)
            val descIdx = cursor.getColumnIndex(CalendarContract.Instances.DESCRIPTION)
            val locIdx = cursor.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
            val beginIdx = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
            val endIdx = cursor.getColumnIndex(CalendarContract.Instances.END)
            val allDayIdx = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)
            val tzIdx = cursor.getColumnIndex(CalendarContract.Events.EVENT_TIMEZONE)
            val colorIdx = cursor.getColumnIndex(CalendarContract.Instances.DISPLAY_COLOR)
            val rruleIdx = cursor.getColumnIndex(CalendarContract.Events.RRULE)
            val syncIdIdx = cursor.getColumnIndex(CalendarContract.Events._SYNC_ID)
            val statusIdx = cursor.getColumnIndex(CalendarContract.Events.STATUS)
            val visIdx = cursor.getColumnIndex(CalendarContract.Events.VISIBLE)

            while (cursor.moveToNext()) {
                val visible = if (visIdx >= 0 && !cursor.isNull(visIdx)) cursor.getInt(visIdx) else 1
                if (visible == 0) continue

                val status = if (statusIdx >= 0 && !cursor.isNull(statusIdx)) {
                    cursor.getInt(statusIdx)
                } else {
                    CalendarContract.Events.STATUS_CONFIRMED
                }
                if (status == CalendarContract.Events.STATUS_CANCELED) continue

                val eventId = if (evIdIdx >= 0) cursor.getLong(evIdIdx) else continue
                val calendarId = if (calIdIdx >= 0) cursor.getLong(calIdIdx) else 1L
                val rawTitle = if (titleIdx >= 0) cursor.getString(titleIdx).orEmpty().trim() else ""
                val title = if (rawTitle.isNotEmpty()) rawTitle else "(Không có tiêu đề)"
                val description = if (descIdx >= 0) cursor.getString(descIdx) else null
                val location = if (locIdx >= 0) cursor.getString(locIdx) else null
                val beginMs = if (beginIdx >= 0) cursor.getLong(beginIdx) else continue
                val rawEndMs = if (endIdx >= 0 && !cursor.isNull(endIdx)) cursor.getLong(endIdx) else 0L
                val isAllDay = if (allDayIdx >= 0) cursor.getInt(allDayIdx) == 1 else false
                val endMs = if (rawEndMs > beginMs) {
                    rawEndMs
                } else {
                    beginMs + if (isAllDay) 86_400_000L else 3_600_000L
                }
                val rrule = if (rruleIdx >= 0) cursor.getString(rruleIdx) else null
                val syncId = if (syncIdIdx >= 0) cursor.getString(syncIdIdx) else null
                val colorInt = if (colorIdx >= 0 && !cursor.isNull(colorIdx)) cursor.getInt(colorIdx) else 0
                val tz = if (tzIdx >= 0) cursor.getString(tzIdx) else null

                // For recurring series on Android, Instances expands each occurrence cleanly.
                // Deduplicate by (eventId, beginMs) so every real occurrence shows accurately on its date!
                val instanceKey = if (!rrule.isNullOrBlank()) {
                    "${eventId}_${beginMs}"
                } else {
                    "$eventId"
                }
                if (!seenKeys.add(instanceKey)) continue

                results.add(
                    mapOf(
                        "instanceKey" to instanceKey,
                        "deviceEventId" to eventId,
                        "deviceCalendarId" to calendarId,
                        "title" to title,
                        "description" to description,
                        "location" to location,
                        "startsAtMs" to beginMs,
                        "endsAtMs" to endMs,
                        "isAllDay" to isAllDay,
                        "timeZone" to (tz ?: TimeZone.getDefault().id),
                        "colorHex" to colorIntToHex(colorInt),
                        "rrule" to null, // Instances already expanded concrete occurrence timestamps
                        "syncId" to syncId
                    )
                )
            }
        }
        return results
    }

    private fun resolveWritableCalendarId(context: Context, preferredId: Long?): Long? {
        val cals = listCalendars(context)
        if (preferredId != null) {
            val match = cals.firstOrNull {
                (it["deviceCalendarId"] as? Long) == preferredId && (it["isReadOnly"] as? Boolean) != true
            }
            if (match != null) return preferredId
        }
        val primaryWritable = cals.firstOrNull {
            (it["isPrimary"] as? Boolean) == true && (it["isReadOnly"] as? Boolean) != true
        }
        if (primaryWritable != null) {
            return primaryWritable["deviceCalendarId"] as? Long
        }
        val anyWritable = cals.firstOrNull { (it["isReadOnly"] as? Boolean) != true }
        if (anyWritable != null) {
            return anyWritable["deviceCalendarId"] as? Long
        }
        return ensureLocalLifeOsCalendar(context)
    }

    private fun ensureLocalLifeOsCalendar(context: Context): Long? {
        return try {
            val values = ContentValues().apply {
                put(CalendarContract.Calendars.ACCOUNT_NAME, "LifeOS")
                put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                put(CalendarContract.Calendars.NAME, "LifeOS_Personal")
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, "Lịch LifeOS")
                put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF0B7A2A.toInt())
                put(
                    CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                    CalendarContract.Calendars.CAL_ACCESS_OWNER
                )
                put(CalendarContract.Calendars.OWNER_ACCOUNT, "LifeOS")
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
                put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
            }
            val syncUri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
                .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, "LifeOS")
                .appendQueryParameter(
                    CalendarContract.Calendars.ACCOUNT_TYPE,
                    CalendarContract.ACCOUNT_TYPE_LOCAL
                )
                .build()
            val inserted = context.contentResolver.insert(syncUri, values)
            inserted?.lastPathSegment?.toLongOrNull()
        } catch (_: Exception) {
            null
        }
    }

    fun upsertEvent(
        context: Context,
        existingDeviceEventId: Long?,
        preferredDeviceCalendarId: Long?,
        title: String,
        description: String?,
        location: String?,
        startsAtMs: Long,
        endsAtMs: Long,
        isAllDay: Boolean,
        timeZone: String?,
        rrule: String?,
        reminderMinutesBefore: Int
    ): Long? {
        if (!hasPermission(context)) return null
        val targetCalId = resolveWritableCalendarId(context, preferredDeviceCalendarId) ?: return null
        val tz = if (!timeZone.isNullOrBlank()) timeZone else TimeZone.getDefault().id

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, targetCalId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description ?: "")
            put(CalendarContract.Events.EVENT_LOCATION, location ?: "")
            put(CalendarContract.Events.DTSTART, startsAtMs)
            if (!rrule.isNullOrBlank()) {
                val durationSec = ((endsAtMs - startsAtMs).coerceAtLeast(60_000L)) / 1000L
                put(CalendarContract.Events.DURATION, "PT${durationSec}S")
                putNull(CalendarContract.Events.DTEND)
                put(CalendarContract.Events.RRULE, rrule.removePrefix("RRULE:"))
            } else {
                put(CalendarContract.Events.DTEND, endsAtMs.coerceAtLeast(startsAtMs + 60_000L))
                putNull(CalendarContract.Events.DURATION)
                putNull(CalendarContract.Events.RRULE)
            }
            put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
            put(CalendarContract.Events.EVENT_TIMEZONE, tz)
            put(CalendarContract.Events.HAS_ALARM, if (reminderMinutesBefore >= 0) 1 else 0)
        }

        var finalEventId: Long? = null
        if (existingDeviceEventId != null && existingDeviceEventId > 0L) {
            val updateUri = ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                existingDeviceEventId
            )
            val rows = context.contentResolver.update(updateUri, values, null, null)
            if (rows > 0) {
                finalEventId = existingDeviceEventId
            }
        }

        if (finalEventId == null) {
            val insertedUri = context.contentResolver.insert(
                CalendarContract.Events.CONTENT_URI,
                values
            )
            finalEventId = insertedUri?.lastPathSegment?.toLongOrNull()
        }

        if (finalEventId != null && finalEventId > 0L) {
            try {
                context.contentResolver.delete(
                    CalendarContract.Reminders.CONTENT_URI,
                    "${CalendarContract.Reminders.EVENT_ID} = ?",
                    arrayOf(finalEventId.toString())
                )
                if (reminderMinutesBefore >= 0) {
                    val remValues = ContentValues().apply {
                        put(CalendarContract.Reminders.EVENT_ID, finalEventId)
                        put(CalendarContract.Reminders.MINUTES, reminderMinutesBefore)
                        put(
                            CalendarContract.Reminders.METHOD,
                            CalendarContract.Reminders.METHOD_ALERT
                        )
                    }
                    context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, remValues)
                }
            } catch (_: Exception) {
            }
        }
        return finalEventId
    }

    fun deleteEvent(context: Context, deviceEventId: Long): Boolean {
        if (!hasPermission(context) || deviceEventId <= 0L) return false
        return try {
            val deleteUri = ContentUris.withAppendedId(
                CalendarContract.Events.CONTENT_URI,
                deviceEventId
            )
            context.contentResolver.delete(deleteUri, null, null) > 0
        } catch (_: Exception) {
            false
        }
    }
}
