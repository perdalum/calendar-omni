import ArgumentParser
import Foundation

struct ExtractCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "extract", abstract: "Extract events; recurring events are excluded unless requested.")
    @OptionGroup var options: CalendarOptions
    @Option(name: .long, help: "First date, inclusive: YYYY-MM-DD.") var from: String
    @Option(name: .long, help: "Last date, inclusive: YYYY-MM-DD.") var to: String
    @Option(name: .long, help: "Case- and diacritic-insensitive title substring.") var filter: String?
    @Option(name: .long, help: "Case-insensitive title regular expression.") var regex: String?
    @Option(name: .long, help: "all or comma-separated title,start,end,location,attendees,notes.") var fields: String = "all"
    @Flag(name: .customLong("include-recurring"), help: "Also include recurring instances and edited series occurrences.") var includeRecurring = false

    @MainActor mutating func run() async throws {
        let input = try validateInput { () -> (TimeZone, Date, Date, [EventField], NSRegularExpression?) in
            let zone = try options.checkedZone()
            let (first, last) = try DateParsing(zone: zone).range(from: from, to: to)
            let fields = try EventField.selection(fields)
            guard filter == nil || regex == nil else { throw OmniError.input("--filter and --regex are mutually exclusive.") }
            guard !(filter?.isEmpty ?? false), !(regex?.isEmpty ?? false) else { throw OmniError.input("Filters must not be empty.") }
            let expression: NSRegularExpression?
            do { expression = try regex.map { try NSRegularExpression(pattern: $0, options: [.caseInsensitive]) } }
            catch { throw OmniError.input("Invalid regular expression: \(error.localizedDescription)") }
            return (zone, first, last, fields, expression)
        }
        try await execute {
            let service = CalendarService(zone: input.0)
            try await service.authorize()
            let calendar = try service.calendar(name: options.calendar, id: options.calendarID)
            let records = try service.extract(calendar: calendar, from: input.1, to: input.2,
                includeRecurring: includeRecurring, filter: filter, regex: input.4)
            try OutputWriter.write(EventOutput(command: "extract", zone: input.0, fields: input.3, records: records), format: options.format)
        }
    }
}
