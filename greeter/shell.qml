// Minimal greetd greeter: black screen, user + password, ascii animation.
// Test inside a normal session with:  qs -p ~/dotfiles/greeter
// (no greetd there → test mode: password "test" quits, anything else fails, Esc quits)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

ShellRoot {
    id: root

    // ───────────────────────── Config ─────────────────────────
    readonly property string defaultUser: ""            // e.g. "jinho" → prefill user, start on password
    readonly property var sessionCommand: ["start-hyprland"]
    readonly property string font: "Iosevka Nerd Font Mono"
    readonly property color fg: "#d0d0d0"
    readonly property color dim: "#3a3a3a"
    readonly property color errorColor: "#a04040"

    readonly property bool testMode: !Greetd.available
    property bool busy: false
    property string pendingPassword: ""
    signal failed()

    function login(user, password) {
        if (busy || user === "")
            return;
        busy = true;
        if (testMode) {
            password === "test" ? Qt.quit() : fail();
            return;
        }
        pendingPassword = password;
        Greetd.createSession(user);
    }

    function fail() {
        if (!testMode && Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        pendingPassword = "";
        busy = false;
        failed();
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.pendingPassword);
                root.pendingPassword = "";
            }
        }
        function onReadyToLaunch() { Greetd.launch(root.sessionCommand) }
        function onAuthFailure(message) { root.fail() }
        function onError(error) { console.warn("greetd:", error); root.fail() }
    }

    // ───────────────────────── Animation ─────────────────────────
    readonly property bool walk: true           // false → stay in the bottom-right corner
    readonly property int walkDirection: 1      // 1 = left → right, -1 = right → left
    readonly property real walkSeconds: 96      // one crossing; the clip loops underneath
    property var frames: []
    property real fps: 12
    // 0 → 1 over one crossing; drives both the frame and the walk position.
    property real progress: 0
    readonly property int frame: frames.length ? Math.floor(progress * walkSeconds * fps) % frames.length : 0

    FileView {
        path: Quickshell.shellPath("ascii/frames.json")
        onLoaded: {
            const data = JSON.parse(text());
            root.fps = data.fps || 12;
            root.frames = data.frames || [];
            if (root.frames.length > 1)
                playback.restart();
        }
    }

    NumberAnimation {
        id: playback
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.walkSeconds * 1000
        loops: Animation.Infinite
    }

    // ───────────────────────── Windows ─────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "greeter"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "black"

            Loader {
                anchors.fill: parent
                focus: true
                active: win.primary
                sourceComponent: screenContent
            }
        }
    }

    Component {
        id: screenContent

        FocusScope {
            focus: true
            Column {
                id: form
                anchors.centerIn: parent
                spacing: 12
                opacity: root.busy ? 0.4 : 1

                Field {
                    id: userField
                    placeholder: "user"
                    text: root.defaultUser
                    focus: root.defaultUser === ""
                    KeyNavigation.tab: passField
                    onAccepted: passField.forceActiveFocus()
                }
                Field {
                    id: passField
                    placeholder: "password"
                    secret: true
                    focus: root.defaultUser !== ""
                    KeyNavigation.tab: userField
                    onAccepted: root.login(userField.text, text)
                }

                SequentialAnimation {
                    id: shake
                    PropertyAnimation { target: form; property: "anchors.horizontalCenterOffset"; to: -10; duration: 40 }
                    PropertyAnimation { target: form; property: "anchors.horizontalCenterOffset"; to: 10; duration: 80 }
                    PropertyAnimation { target: form; property: "anchors.horizontalCenterOffset"; to: -6; duration: 80 }
                    PropertyAnimation { target: form; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
                }

                Connections {
                    target: root
                    function onFailed() {
                        passField.text = "";
                        passField.flash();
                        passField.forceActiveFocus();
                        shake.restart();
                    }
                }
            }

            Text {
                // Walking: enter fully off one edge, leave fully off the other.
                readonly property real travel: parent.width + width
                x: !root.walk ? parent.width - width - 32
                   : root.walkDirection > 0 ? root.progress * travel - width
                   : parent.width - root.progress * travel
                y: parent.height - height - 32
                text: root.frames.length ? root.frames[root.frame] : ""
                textFormat: Text.PlainText
                font { family: root.font; pixelSize: 11 }
                lineHeight: 0.9
                color: root.fg
            }
        }
    }

    component Field: FocusScope {
        id: field
        property alias text: input.text
        property string placeholder
        property bool secret: false
        property bool error: false
        signal accepted()

        function flash() { error = true; errorTimer.restart() }

        width: 260
        height: 34

        Timer { id: errorTimer; interval: 900; onTriggered: field.error = false }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: field.error ? root.errorColor : input.activeFocus ? "#707070" : root.dim
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            focus: true
            enabled: !root.busy
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            color: root.fg
            selectionColor: "#444444"
            font { family: root.font; pixelSize: 14 }
            cursorDelegate: Rectangle {
                width: 1
                color: root.fg
                visible: input.activeFocus
            }
            Keys.onEscapePressed: root.testMode ? Qt.quit() : input.clear()
            onAccepted: field.accepted()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: field.placeholder
                color: root.dim
                font: input.font
            }
        }
    }
}
