import SwiftUI

/// Twelve Sunday-first weeks. Missing dates are empty; future dates are blank.
///
/// The scale runs through the sage tone rather than a system green, and empty
/// days are a warm well rather than a grey — on cream paper a neutral grey
/// square reads as a hole, while the well reads as "nothing yet".
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
        VStack(alignment: .leading, spacing: BuddyTheme.gapSnug) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(0..<7) { row in
                        Text(row == 1 ? (language == "ko" ? "월" : "M") : row == 3 ? (language == "ko" ? "수" : "W") : row == 5 ? (language == "ko" ? "금" : "F") : "")
                            .font(.system(size: 8)).frame(width: 12, height: 15)
                    }
                }.foregroundStyle(BuddyTheme.inkFaint)
                ForEach(0..<12) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7) { weekday in
                            cell(days[week * 7 + weekday])
                        }
                    }
                }
            }
            HStack(spacing: BuddyTheme.gapSnug) {
                Text(language == "ko" ? "최근 12주" : "Last 12 weeks")
                    .font(.system(size: 10)).foregroundStyle(BuddyTheme.inkFaint)
                Spacer(minLength: 0)
                legend
            }
            .padding(.leading, 16)
        }
    }

    /// Less / more, four steps, matching the cell scale exactly.
    private var legend: some View {
        HStack(spacing: 3) {
            Text(language == "ko" ? "적음" : "Less")
                .font(.system(size: 9)).foregroundStyle(BuddyTheme.inkFaint)
            ForEach([0.0, 0.35, 0.6, 0.8, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? BuddyTheme.well : BuddyTheme.green.opacity(level))
                    .frame(width: 8, height: 8)
            }
            Text(language == "ko" ? "많음" : "More")
                .font(.system(size: 9)).foregroundStyle(BuddyTheme.inkFaint)
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: Date) -> some View {
        let key = CivilDay.localDay(at: day.timeIntervalSince1970 * 1000, calendar: .current)
        let entry = activity.first { $0.day == key }
        let turns = entry?.turns ?? 0
        let future = day > date
        let today = key == CivilDay.localDay(at: date.timeIntervalSince1970 * 1000, calendar: .current)
        let level = turns == 0 ? 0.0 : turns < 5 ? 0.35 : turns < 15 ? 0.6 : turns < 30 ? 0.8 : 1.0
        let label = language == "ko" ? "\(key): \(turns)턴" : "\(key): \(turns) completed turns"
        // A day Buddy was used but that landed no completed turn still gets a
        // ring, so "I was here" is visible without inflating the count scale.
        let ring: Color = today ? BuddyTheme.accentInk
            : (entry?.active == true && turns == 0) ? BuddyTheme.green.opacity(0.55) : .clear
        return RoundedRectangle(cornerRadius: 2)
            .fill(future ? Color.clear : turns > 0 ? BuddyTheme.green.opacity(level) : BuddyTheme.well)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(ring, lineWidth: 1))
            .frame(width: 15, height: 15)
            .help(future ? "" : label + ((entry?.active == true && turns == 0) ? (language == "ko" ? " · 활동한 날" : " · Buddy used") : ""))
            .accessibilityLabel(label).accessibilityHidden(future)
    }
}
