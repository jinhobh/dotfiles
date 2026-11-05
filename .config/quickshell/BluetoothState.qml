pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter ? adapter.enabled : false
    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string statePath: stateDir + "/bluetooth-state.json"
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool btSink: !!(sink && sink.name && sink.name.indexOf("bluez") >= 0)

    // Never starts a connection on its own: those only happen when the user asks (Connect in
    // Settings, or bluetoothctl). Auto-connecting steals devices like AirPods from whatever
    // other host (e.g. a phone) is using them. Trusted devices may still connect themselves.
    property var removingDevices: ({})
    property BluetoothDevice pairTarget: null
    property var linkSeen: ({})
    property int audioGraceMs: 5000
    property int removalHideDurationMs: 10000
    property var deviceVolumes: ({})
    property bool stateLoaded: false
    property string trackedSink: ""
    property real settleUntil: 0
    property int settleMs: 6000
    onBtSinkChanged: if (!btSink) trackedSink = ""
    

    function init() {}

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        onLoaded: root.loadState()
        onLoadFailed: error => root.stateLoaded = true
    }

    function deviceList() {
        if (!root.adapter || !root.adapter.devices)
            return []
        var d = root.adapter.devices
        return d.values !== undefined ? d.values : d
    }

    function loadState() {
        var text = stateFile.text()
        if (text) {
            try {
                var s = JSON.parse(text)
                if (s && typeof s === "object") {
                    if (s.removing && typeof s.removing === "object")
                        root.removingDevices = s.removing
                    if (s.volumes && typeof s.volumes === "object")
                        root.deviceVolumes = s.volumes
                }
            } catch (error) {
                console.warn("bluetooth: could not read saved state:", error)
            }
        }
        root.stateLoaded = true
        root.pruneRemovingDevices()
    }

    function saveState() {
        if (!root.stateLoaded)
            return
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: stateFile.setText(JSON.stringify({
            removing: root.removingDevices,
            volumes: root.deviceVolumes
        }))
    }

    function markRemoved(dev) {
        if (!dev)
            return
        var key = dev.address || dev.name || ""
        if (!key)
            return
        var updated = Object.assign({}, root.removingDevices)
        updated[key] = Date.now()
        root.removingDevices = updated
        if (dev.address && root.deviceVolumes[dev.address] !== undefined) {
            var vols = Object.assign({}, root.deviceVolumes)
            delete vols[dev.address]
            root.deviceVolumes = vols
        }
        root.saveState()
    }

    function pruneRemovingDevices() {
        var now = Date.now()
        var present = ({})
        var devs = root.deviceList()

        for (var i = 0; i < devs.length; i++) {
            var key = devs[i].address || devs[i].name || ""
            if (key) present[key] = true
        }

        var updated = {}
        var changed = false

        for (var k in root.removingDevices) {
            var ts = root.removingDevices[k]
            if (present[k] && (now - ts) <= root.removalHideDurationMs)
                updated[k] = ts
            else
                changed = true
        }

        if (changed) {
            root.removingDevices = updated
            root.saveState()
        }
    }

    function sinkAddressFor(node) {
        if (!node || !node.name || node.name.indexOf("bluez") < 0)
            return ""
        var name = node.name.toUpperCase()
        var devs = root.deviceList()
        for (var i = 0; i < devs.length; i++) {
            var a = devs[i].address
            if (a && name.indexOf(a.toUpperCase().replace(/:/g, "_")) >= 0)
                return a
        }
        return ""
    }

    function volumeTick() {
        if (!root.stateLoaded)
            return

        var node = root.sink
        var addr = root.sinkAddressFor(node)

        if (!node || !node.audio || addr === "") {
            root.trackedSink = ""
            return
        }

        if (root.trackedSink !== node.name) {
            root.trackedSink = node.name
            root.settleUntil = Date.now() + root.settleMs
        }

        var saved = root.deviceVolumes[addr]
        var current = node.audio.volume

        if (Date.now() < root.settleUntil) {
            if (typeof saved === "number" && Math.abs(current - saved) > 0.005)
                node.audio.volume = Math.max(0, Math.min(1.0, saved))
            return
        }

        var v = Math.round(current * 100) / 100
        if (saved === v)
            return

        var updated = Object.assign({}, root.deviceVolumes)
        updated[addr] = v
        root.deviceVolumes = updated
        root.saveState()
    }

    Timer {
        interval: 250
        running: root.stateLoaded && root.btSink
        repeat: true
        onTriggered: root.volumeTick()
    }

    // No pairing agent is registered, and without one BlueZ leaves the adapter non-bondable:
    // pairings then work for one session but are never saved, so the device has to be
    // re-paired next time. Keep it bondable whenever it's on.
    function keepBondable() {
        if (root.adapter && root.adapter.enabled && !root.adapter.pairable)
            root.adapter.pairable = true
    }

    onAdapterChanged: keepBondable()
    Component.onCompleted: keepBondable()

    Connections {
        target: root.adapter
        function onEnabledChanged() { root.keepBondable() }
    }

    // Connect from Settings on a device that isn't paired yet: pair first so the bond is
    // saved, then connect once pairing finishes.
    function pairThenConnect(dev) {
        root.keepBondable()
        root.pairTarget = dev
        dev.pair()
    }

    Connections {
        target: root.pairTarget
        function onPairingChanged() {
            if (!root.pairTarget.pairing)
                pairDone.restart()
        }
    }

    Timer {
        id: pairDone
        interval: 500
        onTriggered: {
            var dev = root.pairTarget
            root.pairTarget = null
            if (dev && dev.paired)
                root.connectProfiles(dev)
        }
    }

    // BluetoothDevice.connect() refuses once the link is up ("already connected"), which it is
    // after pairing or when the device connected itself. BlueZ's Device1.Connect still connects
    // the profiles that are missing.
    function connectProfiles(dev) {
        Quickshell.execDetached(["busctl", "call", "--timeout=30", "org.bluez", dev.dbusPath,
                                 "org.bluez.Device1", "Connect"])
    }

    function hasAudioNode(address) {
        var key = address.toUpperCase().replace(/:/g, "_")
        var nodes = Pipewire.nodes.values
        for (var i = 0; i < nodes.length; i++) {
            if (!nodes[i].isStream && nodes[i].name && nodes[i].name.toUpperCase().indexOf(key) >= 0)
                return true
        }
        return false
    }

    // A paired audio device that connects itself (AirPods do when the case opens) can bring up
    // just the link and no audio profiles, which leaves no output to pick. Finish connecting its
    // profiles once per connection. This only acts on a link the device already opened.
    function completeAudioLinks() {
        if (!Pipewire.ready)
            return
        var now = Date.now()
        var seen = ({})
        var devs = root.deviceList()

        for (var i = 0; i < devs.length; i++) {
            var d = devs[i]
            if (!d.address || d.state !== BluetoothDeviceState.Connected)
                continue
            var entry = root.linkSeen[d.address] || { since: now, done: false }
            seen[d.address] = entry

            if (entry.done || now - entry.since < root.audioGraceMs)
                continue
            entry.done = true
            if (d.bonded && (d.icon || "").indexOf("audio") === 0 && !root.hasAudioNode(d.address))
                root.connectProfiles(d)
        }
        root.linkSeen = seen
    }

    Timer {
        interval: 2000
        running: root.stateLoaded
        repeat: true
        onTriggered: {
            root.pruneRemovingDevices()
            root.completeAudioLinks()
        }
    }
}