// Marquee.qml — shared MPRIS + marquee state (one ticker for all screens)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Scope {
    id: root

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string title: player
        ? ((player.trackArtist ? player.trackArtist + " - " : "") + player.trackTitle)
        : ""
    // nf-md play / pause
    readonly property string text: (playing ? "\uDB81\uDC0A " : "\uDB80\uDFE4 ") + title

    // Set by the bar's media module; VolumeOsd shows the media popup while true.
    property bool barHovered: false
    property Item hoveredItem: null

    // The media module on every bar registers here so the popup can open right
    // next to it. Each item has place() → { screen, rect (screen-local), edge } or null.
    property var mediaItems: []
    function register(item) { mediaItems = mediaItems.concat([item]) }
    function unregister(item) {
        mediaItems = mediaItems.filter(i => i !== item)
        if (hoveredItem === item) { hoveredItem = null; barHovered = false }
    }
    // The visible media module on the named screen (any screen if empty).
    function locate(screenName) {
        for (const item of mediaItems) {
            const p = item.place()
            if (p && (screenName === "" || p.screen.name === screenName))
                return p
        }
        return null
    }

    readonly property int maxW: 130       // visible width in px
    readonly property int gap: 20         // gap between the two copies
    readonly property int step: 1         // px per tick (integer = crisp text)
    readonly property int interval: 33    // ms per tick (~30 fps); 50 = 20 fps
    readonly property int holdMs: 2500    // idle pause at the start of each loop

    readonly property real textW: measure.implicitWidth
    readonly property bool animating: playing && textW > maxW

    property int x: 0
    property bool hold: true

    // Invisible text, only used to measure the width
    Item {
        visible: false
        Text {
            id: measure
            text: root.text
            font.family: "Noto Sans CJK KR"
            font.pixelSize: 11
        }
    }

    onAnimatingChanged: { x = 0; hold = true; }
    onTitleChanged: { x = 0; hold = true; }

    // Runs whenever we are scrolling-capable AND holding at the start.
    Timer {
        interval: root.holdMs
        repeat: false
        running: root.animating && root.hold
        onTriggered: root.hold = false
    }

    // Runs only while text actually scrolls; otherwise zero repaints.
    Timer {
        interval: root.interval
        repeat: true
        running: root.animating && !root.hold
        onTriggered: {
            root.x -= root.step;
            if (root.x <= -(root.textW + root.gap)) {
                root.x = 0;
                root.hold = true;
            }
        }
    }
}