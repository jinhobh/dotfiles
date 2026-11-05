import Quickshell
import Quickshell.Io

ShellRoot {
    VolumeOsd {}
    ScreenshotOsd {}
    SettingsWindow {}
    Notifications {}
    PowerMenu {}
    Bar {}
    Todo {}
    Wheel {}

    // `qs ipc call shell reload` — reload in place instead of `qs kill`,
    // which currently crashes on shutdown and auto-restarts (duplicate bars).
    IpcHandler {
        target: "shell"
        function reload(): void { Qt.callLater(() => Quickshell.reload(true)) }
    }
}
