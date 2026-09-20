import ArgumentParser
import Foundation

struct ReportOptions: ParsableArguments {
    @Option(name: .long, help: "YAML config file with calendars, fields, and datetime_format.", completion: .file())
    var config = "~/.calendar-omni"

    @MainActor func run(_ period: ReportPeriod) async throws {
        let settings = try validateInput { try ReportConfig.load(path: config) }
        let dates = DateParsing(zone: .current)
        let (start, end) = period.range(now: Date(), dates: dates)
        try await execute {
            let service = CalendarService(zone: dates.zone)
            try await service.authorize()
            var records: [EventRecord] = []
            for name in settings.calendars {
                let calendar = try service.calendar(name: name, id: nil)
                records += try service.extract(calendar: calendar, from: start, to: end,
                    includeRecurring: true, filter: nil, regex: nil)
            }
            let data = try period.data(records: records, config: settings, dates: dates)
            do { try FileHandle.standardOutput.write(contentsOf: data) }
            catch { throw OmniError.operation("Output failed: \(error.localizedDescription)") }
        }
    }
}

struct TodayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "today", abstract: "Today's configured calendars as FROM -- TO : TITLE, including recurring events.")
    @OptionGroup var options: ReportOptions
    @MainActor mutating func run() async throws { try await options.run(.today) }
}

struct TomorrowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tomorrow", abstract: "Tomorrow's configured calendars as FROM -- TO : TITLE, including recurring events.")
    @OptionGroup var options: ReportOptions
    @MainActor mutating func run() async throws { try await options.run(.tomorrow) }
}

struct LastWeekCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "last-week", abstract: "Previous Monday–Sunday from configured calendars as semicolon CSV, including recurring events.")
    @OptionGroup var options: ReportOptions
    @MainActor mutating func run() async throws { try await options.run(.lastWeek) }
}
