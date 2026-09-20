import ArgumentParser
import Foundation
import Darwin

extension OutputFormat: ExpressibleByArgument {}

@main
struct CalendarOmni: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "CalendarOmni", abstract: "Extract, create, and update Apple Calendar events.",
        version: "0.0.1", subcommands: [ExtractCommand.self, CreateCommand.self, UpdateCommand.self])

    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        do {
            var command = try parseAsRoot()
            if var asynchronous = command as? any AsyncParsableCommand {
                try await asynchronous.run()
            } else { try command.run() }
        } catch {
            // Argument Parser uses EX_USAGE (64); this tool promises exit 2 for input errors.
            if exitCode(for: error) == .validationFailure {
                try? FileHandle.standardError.write(contentsOf: Data((fullMessage(for: error) + "\n").utf8))
                Darwin.exit(2)
            }
            exit(withError: error)
        }
    }
}

struct CalendarOptions: ParsableArguments {
    @Option(name: .long, help: "Exact, case-sensitive calendar name.") var calendar: String?
    @Option(name: .customLong("calendar-id"), help: "Exact calendar ID instead of a name.") var calendarID: String?
    @Option(name: .customLong("time-zone"), help: "IANA time zone; defaults to this Mac's zone.") var timeZone: String?
    @Option(name: .long, help: "Output format: json or semicolon csv.") var format: OutputFormat = .json

    func checkedZone() throws -> TimeZone {
        guard (calendar == nil) != (calendarID == nil), !(calendar?.isEmpty ?? false), !(calendarID?.isEmpty ?? false) else {
            throw OmniError.input("Supply exactly one nonempty --calendar or --calendar-id.")
        }
        return try DateParsing.timeZone(timeZone)
    }
}

func validateInput<T>(_ action: () throws -> T) throws -> T {
    do { return try action() }
    catch OmniError.input(let message) { throw ValidationError(message) }
}

// Translate preflight errors consistently even if they require live target data.
@MainActor func execute(_ action: @MainActor () async throws -> Void) async throws {
    signal(SIGPIPE, SIG_IGN)
    do { try await action() }
    catch OmniError.input(let message) { throw ValidationError(message) }
}
