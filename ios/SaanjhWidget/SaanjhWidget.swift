/*
 * SaanjhWidget — iOS WidgetKit extension
 *
 * SETUP (one-time, in Xcode):
 * 1. File → New → Target → Widget Extension → name it "SaanjhWidget".
 * 2. Runner target → Signing & Capabilities → + App Groups
 *    Add: group.com.saanjh.saanjh
 * 3. SaanjhWidget target → Signing & Capabilities → + App Groups
 *    Add the same group.
 * 4. In Apple Developer Portal → Identifiers → add the App Group.
 * 5. Build from Xcode — the widget appears in the iOS widget gallery.
 *
 * Data is written by HomeWidgetService (Dart) via UserDefaults with
 * the shared suite name "group.com.saanjh.saanjh".
 */

import WidgetKit
import SwiftUI

// ─── Shared group key ─────────────────────────────────────────────────────────

private let appGroupId = "group.com.saanjh.saanjh"

// ─── Data model ──────────────────────────────────────────────────────────────

struct SaanjhEntry: TimelineEntry {
    let date: Date
    let contactName: String
    let streakDays: Int
    let pulseTime: String
    let wasHere: Bool
}

// ─── Provider ────────────────────────────────────────────────────────────────

struct SaanjhProvider: TimelineProvider {

    func placeholder(in context: Context) -> SaanjhEntry {
        SaanjhEntry(date: Date(), contactName: "Name", streakDays: 7,
                    pulseTime: "9:00 AM", wasHere: true)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (SaanjhEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<SaanjhEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 30 minutes; the app also triggers explicit refreshes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> SaanjhEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return SaanjhEntry(
            date: Date(),
            contactName: defaults?.string(forKey: "contact_name") ?? "—",
            streakDays:  defaults?.integer(forKey: "streak_days") ?? 0,
            pulseTime:   defaults?.string(forKey: "pulse_time") ?? "",
            wasHere:     defaults?.bool(forKey: "was_here") ?? false
        )
    }
}

// ─── Small view (2×2) ────────────────────────────────────────────────────────

struct SaanjhSmallView: View {
    let entry: SaanjhEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.contactName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.96, green: 0.94, blue: 0.91))
                .lineLimit(1)

            if entry.wasHere {
                Text("💛 was here")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.58, blue: 0))
            }

            Spacer()

            Text(entry.streakDays > 0 ? "🔥 \(entry.streakDays)" : "🔥 —")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 1, green: 0.63, blue: 0.25))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.10, green: 0.03, blue: 0))
    }
}

// ─── Medium view (2×4) ───────────────────────────────────────────────────────

struct SaanjhMediumView: View {
    let entry: SaanjhEntry

    var pulseLabel: String {
        if entry.wasHere && !entry.pulseTime.isEmpty {
            return "\(entry.contactName) was here at \(entry.pulseTime)"
        } else if entry.wasHere {
            return "\(entry.contactName) was here today"
        }
        return entry.contactName
    }

    var body: some View {
        HStack(alignment: .center) {
            // Left: name + pulse
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.contactName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.96, green: 0.94, blue: 0.91))
                    .lineLimit(1)

                if entry.wasHere {
                    Text(entry.pulseTime.isEmpty
                         ? "💛 was here today"
                         : "💛 was here at \(entry.pulseTime)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 1, green: 0.58, blue: 0))
                }
            }

            Spacer()

            // Right: streak + CTA
            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.streakDays > 0 ? "🔥 \(entry.streakDays)" : "🔥 —")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 1, green: 0.63, blue: 0.25))

                Text("Record →")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 1, green: 0.58, blue: 0))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.03, blue: 0))
    }
}

// ─── Widget entry view (size-adaptive) ───────────────────────────────────────

struct SaanjhWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SaanjhEntry

    var body: some View {
        switch family {
        case .systemMedium:
            SaanjhMediumView(entry: entry)
        default:
            SaanjhSmallView(entry: entry)
        }
    }
}

// ─── Widget declaration ──────────────────────────────────────────────────────

@main
struct SaanjhWidget: Widget {
    let kind = "SaanjhWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SaanjhProvider()) { entry in
            SaanjhWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Saanjh")
        .description("See your diary at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
