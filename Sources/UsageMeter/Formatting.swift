import Foundation

enum Fmt {
    /// True when the user's system clock preference is 24-hour time.
    private static var uses24Hour: Bool {
        let fmt = DateFormatter.dateFormat(
            fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !fmt.contains("a")
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        // Pin the locale so explicit patterns aren't rewritten by the system.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }

    /// Compact reset time for the menu bar title: "3pm" / "9:15am", or "14:11"
    /// on 24-hour systems. Prefixed with the weekday when not today.
    static func compactTime(_ date: Date) -> String {
        let cal = Calendar.current
        var pattern: String
        if uses24Hour {
            pattern = "H:mm"
        } else {
            pattern = cal.component(.minute, from: date) == 0 ? "ha" : "h:mma"
        }
        if !cal.isDateInToday(date) { pattern = "EEE " + pattern }
        return formatter(pattern).string(from: date)
    }

    /// Full reset time for menu rows: "3:00 PM" / "14:11", "Thu 9:15 AM".
    static func fullTime(_ date: Date) -> String {
        var pattern = uses24Hour ? "H:mm" : "h:mm a"
        if !Calendar.current.isDateInToday(date) { pattern = "EEE " + pattern }
        let f = formatter(pattern)
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: date)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value.rounded())
    }

    /// Menu bar title for the selected service, e.g. "✳ 72% · 3pm".
    static func statusTitle(kind: ServiceKind, state: ServiceState) -> String {
        switch state {
        case .loading:
            return "\(kind.glyph) …"
        case .error, .notConfigured:
            return "\(kind.glyph) —"
        case .ok(let snap):
            let pct = percent(snap.fiveHour.remainingPercent)
            return "\(kind.glyph) \(pct) · \(compactTime(snap.fiveHour.resetsAt))"
        }
    }
}
