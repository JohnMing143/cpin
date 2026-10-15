import AppKit

@main
enum CpinMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate(isDemo: CommandLine.arguments.contains("--demo"))
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
