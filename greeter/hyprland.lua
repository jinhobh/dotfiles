-- Compositor for the login screen only (runs as the `greeter` user under greetd).
-- Starts the Quickshell greeter, then exits Hyprland once it has launched your session.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
    input = {
        kb_layout = "us",
        touchpad = { tap_to_click = true },
    },
    animations = { enabled = false },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("QSG_RENDER_LOOP=basic qs -p /etc/greetd/greeter; hyprctl dispatch 'hl.dsp.exit()'")
end)
