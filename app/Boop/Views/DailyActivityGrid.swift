import SwiftUI

/// Twelve Sunday-first weeks. Missing dates are empty; future dates are blank.
struct DailyActivityGrid: View {
    let activity: [DailyActivity]
    var date = Date()
    var language = "en"
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let sunday = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: today), to: today)!
        let start = calendar.date(byAdding: .day, value: -77, to: sunday)!
        return (0..<84).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 3) {
                    ForEach(0..<7) { row in
                        Text(row == 1 ? (language == "ko" ? "월" : "M") : row == 3 ? (language == "ko" ? "수" : "W") : row == 5 ? (language == "ko" ? "금" : "F") : "")
                            .font(.system(size: 8)).frame(width: 12, height: 9)
                    }
                }.foregroundStyle(.secondary)
                ForEach(0..<12) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7) { weekday in
                            cell(days[week * 7 + weekday])
                        }
                    }
                }
            }
            Text(language == "ko" ? "최근 12주" : "Last 12 weeks")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
    }
    private func cell(_ day: Date) -> some View {
        let key = CivilDay.localDay(at: day.timeIntervalSince1970 * 1000, calendar: .current)
        let entry = activity.first { $0.day == key }
        let turns = entry?.turns ?? 0
        let future = day > date
        let opacity = turns == 0 ? 0.08 : turns < 5 ? 0.3 : turns < 15 ? 0.5 : turns < 30 ? 0.75 : 1.0
        let label = language == "ko" ? "\(key): \(turns)턴" : "\(key): \(turns) completed turns"
        return RoundedRectangle(cornerRadius: 2)
            .fill(future ? Color.clear : turns > 0 ? Color.green.opacity(opacity) : Color.secondary.opacity(opacity))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(entry?.active == true && turns == 0 ? Color.green.opacity(0.5) : .clear, lineWidth: 1))
            .frame(maxWidth: .infinity).frame(height: 9)
            .help(future ? "" : label + ((entry?.active == true && turns == 0) ? (language == "ko" ? " · 활동한 날" : " · Buddy used") : ""))
            .accessibilityLabel(label).accessibilityHidden(future)
    }
}
