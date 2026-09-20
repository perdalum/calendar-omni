import ArgumentParser
import Foundation
import Darwin

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create one timed, non-recurring event.")
    @OptionGroup var options: CalendarOptions
    @Option(name: .long) var title: String
    @Option(name: .long, help: "Civil date: YYYY-MM-DD.") var date: String
    @Option(name: .long, help: "Start time: H:mm or HH:mm.") var start: String
    @Option(name: .long, help: "Later clock time on the same date.") var end: String?
    @Option(name: .long, help: "Elapsed duration instead of --end: 1h30m, 2h, or 45m.") var duration: String?
    @Option(name: .long) var location: String?
    @Option(name: .long) var notes: String?
    @Flag(name: .customLong("notes-stdin"), help: "Read notes verbatim from piped UTF-8 stdin.") var notesStdin = false

    @MainActor mutating func run() async throws {
        let input = try validateInput { () -> (TimeZone, Date, Date, String?) in
            let zone = try options.checkedZone()
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OmniError.input("Title must not be blank.") }
            let (first, last) = try DateParsing(zone: zone).creationDates(date: date, start: start, end: end, duration: duration)
            guard notes == nil || !notesStdin else { throw OmniError.input("--notes and --notes-stdin are mutually exclusive.") }
            var text = notes
            if notesStdin {
                guard isatty(STDIN_FILENO) == 0 else { throw OmniError.input("--notes-stdin requires piped input.") }
                let data = try FileHandle.standardInput.readToEnd() ?? Data()
                guard let value = String(data: data, encoding: .utf8) else { throw OmniError.input("Notes must be UTF-8.") }
                text = value
            }
            return (zone, first, last, text)
        }
        try await execute {
            let service = CalendarService(zone: input.0)
            try await service.authorize()
            let calendar = try service.calendar(name: options.calendar, id: options.calendarID)
            let record = try service.create(calendar: calendar, title: title, start: input.1, end: input.2, location: location, notes: input.3)
            try OutputWriter.write(EventOutput(command: "create", zone: input.0, records: [record]), format: options.format, saved: true)
        }
    }
}
