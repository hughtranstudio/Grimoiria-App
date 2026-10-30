import GrimoireAppKit
import GrimoireCore
import SwiftUI

extension MoonPhase {
    var symbol: String {
        switch self {
        case .new: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .full: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

extension SkyEvent {
    var symbol: String {
        switch kind {
        case .newMoon: MoonPhase.new.symbol
        case .firstQuarter: MoonPhase.firstQuarter.symbol
        case .fullMoon: MoonPhase.full.symbol
        case .lastQuarter: MoonPhase.lastQuarter.symbol
        case .moonIngress: "moon"
        case .sunIngress: "sun.max"
        }
    }
}

extension AppModel {
    /// The days of the month the Calendar shows, reckoned at the home location.
    var calendarDays: [CalendarDay] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: calendarMonth)) ?? calendarMonth
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        return RitualCalendar.days(from: GrimoireDateFormat.day(start, in: .current), count: count, zone: .current, location: settings.home)
    }

    /// Filed records and readings on a day.
    func records(on day: String) -> (entries: [Entry], inquiries: [Inquiry]) {
        (timelineEntries.filter { $0.occurredAt.day == day }, data.inquiries.filter { $0.askedAt.day == day })
    }

    /// A ritual entry planned for a moment, such as the start of a planetary hour.
    func newRitual(at date: Date, intention: String? = nil) {
        let at = ZonedDate(date, timeZone: TimeZone.current.identifier)
        var e = Entry(type: .ritual, occurredAt: at, timing: timing(at: at), mode: .reflective)
        e.fields.intention = intention
        repository.save(e)
        page = .timeline
        selection = .entry(e.id)
    }

    func moveCalendar(months: Int) {
        calendarMonth = Calendar.current.date(byAdding: .month, value: months, to: calendarMonth) ?? calendarMonth
        selection = nil
    }
}

private func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

/// The middle column: every day of a month with its ruler, the Moon, events, and what was logged.
struct CalendarList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let days = model.calendarDays
        List(selection: $model.selection) {
            if model.settings.home == nil {
                Label {
                    Text("Set a home location in Settings > General for sunrise, sunset and planetary hours.").font(Typo.body)
                } icon: {
                    Image(systemName: "location.slash")
                }
                .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(days, id: \.day) { d in
                CalendarDayRow(day: d, isToday: d.day == model.today)
                    .tag(Selection.day(d.day))
            }
        }
        .navigationTitle(model.calendarMonth.formatted(.dateTime.month(.wide).year()))
        .toolbar {
            ToolbarItemGroup {
                Button("Previous Month", systemImage: "chevron.left") { model.moveCalendar(months: -1) }
                    .help("Previous month (Command-Option-Left Arrow)")
                Button("This Month") {
                    model.calendarMonth = .now
                    model.selection = .day(model.today)
                }
                .help("Back to today (Command-Option-Y)")
                Button("Next Month", systemImage: "chevron.right") { model.moveCalendar(months: 1) }
                    .help("Next month (Command-Option-Right Arrow)")
            }
        }
    }
}

struct CalendarDayRow: View {
    @Environment(AppModel.self) private var model
    let day: CalendarDay
    let isToday: Bool

    var body: some View {
        let logged = model.records(on: day.day)
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: day.moonPhase.symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(DisplayDate.day(day.day)).font(Typo.body).fontWeight(isToday ? .semibold : .regular)
                    Text("\(CardGlyph.symbol(for: day.ruler)) \(day.ruler.rawValue.capitalized)").font(Typo.body).foregroundStyle(.secondary)
                    if isToday { Text("Today").font(Typo.caption).foregroundStyle(.tint) }
                }
                ForEach(day.events, id: \.self) { e in
                    Label("\(clock(e.at))  \(e.title)", systemImage: e.symbol)
                        .font(Typo.caption)
                        .foregroundStyle(e.isPhase ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                let rituals = logged.entries.filter { $0.type == .ritual }.count
                let others = logged.entries.count - rituals + logged.inquiries.count
                if rituals + others > 0 {
                    Text([rituals > 0 ? "\(rituals) ritual\(rituals == 1 ? "" : "s")" : nil,
                          others > 0 ? "\(others) other record\(others == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }
}

/// One day: the Moon, events, planetary hours (plan a ritual in one), and what was logged.
struct CalendarDayDetail: View {
    @Environment(AppModel.self) private var model
    let day: String

    var body: some View {
        if let d = RitualCalendar.day(day, zone: .current, location: model.settings.home) {
            let logged = model.records(on: day)
            Form {
                Section {
                    LabeledContent("Day of", value: "\(CardGlyph.symbol(for: d.ruler)) \(d.ruler.rawValue.capitalized)")
                    LabeledContent("Moon at noon") {
                        Label("\(TimingText.phase(d.moonPhase)) \(d.moonIllumination)% in \(d.moonSign.rawValue.capitalized)",
                              systemImage: d.moonPhase.symbol)
                    }
                    LabeledContent("Sun in", value: d.sunSign.rawValue.capitalized)
                    if let rise = d.sunrise, let set = d.sunset {
                        LabeledContent("Sunrise and sunset", value: "\(clock(rise)) · \(clock(set))")
                    }
                }
                if !d.events.isEmpty {
                    Section("In the sky") {
                        ForEach(d.events, id: \.self) { e in
                            LabeledContent { Text(clock(e.at)) } label: { Label(e.title, systemImage: e.symbol) }
                        }
                    }
                }
                Section {
                    if logged.entries.isEmpty && logged.inquiries.isEmpty {
                        Text("Nothing logged on this day.").foregroundStyle(.secondary)
                    }
                    ForEach(logged.inquiries) { i in
                        Button { model.reveal(i.id) } label: { InquiryRow(inquiry: i) }.buttonStyle(.plain)
                    }
                    ForEach(logged.entries) { e in
                        Button { model.reveal(e.id) } label: { EntryRow(entry: e) }.buttonStyle(.plain)
                    }
                } header: {
                    Text("Logged")
                }
                if !d.hours.isEmpty {
                    Section {
                        ForEach(d.hours, id: \.number) { h in
                            let now = (h.start...h.end).contains(.now)
                            HStack {
                                Text("\(h.number)").monospacedDigit().foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                                Text("\(CardGlyph.symbol(for: h.planet)) \(h.planet.rawValue.capitalized)")
                                    .fontWeight(now ? .semibold : .regular)
                                if now { Text("Now").font(Typo.caption).foregroundStyle(.tint) }
                                Spacer()
                                Text("\(clock(h.start)) – \(clock(h.end))").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("New Ritual in This Hour") {
                                    model.newRitual(at: h.start, intention: "Hour of \(h.planet.rawValue.capitalized)")
                                }
                            }
                        }
                    } header: {
                        Text("Planetary hours")
                    } footer: {
                        Text("The magical day runs from sunrise to the next sunrise. Right-click an hour to plan a ritual in it.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(DisplayDate.day(day))
        } else {
            ContentUnavailableView("No Such Day", systemImage: "calendar")
        }
    }
}
