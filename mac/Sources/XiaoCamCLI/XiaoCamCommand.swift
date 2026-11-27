import ArgumentParser

@main
struct XiaoCamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xiaocam",
        abstract: "See through the XIAO Wi-Fi camera. Capture commands print one file path.",
        discussion: """
        Exit codes: 0 success, 2 camera offline, 3 XiaoCam app not running or it quit, 4 busy, \
        5 job or result not found, 64 bad arguments, 1 other failures.
        """,
        subcommands: [
            StatusCommand.self,
            DiscoverCommand.self,
            ConnectCommand.self,
            SnapCommand.self,
            GridCommand.self,
            ClipCommand.self,
            JobCommand.self,
            JobsCommand.self,
            ModeCommand.self,
            SetCommand.self,
            ConfigCommand.self,
        ]
    )
}
