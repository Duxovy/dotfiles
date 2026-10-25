# Quickshell Desktop Lyrics Widget

A lightweight, click-through, and customizable desktop lyrics overlay for Wayland compositors, built with **Quickshell** and **sptlrx**.

## Features

- **Always-on-Top & Click-Through (Ghost Mode):** Stays visible over fullscreen and tiled windows (`WlrLayer.Overlay`) while letting all mouse clicks pass directly through to the applications behind it.
- **Interactive Drag Mode:** Unlock the widget via an IPC command to drag and reposition it anywhere on the screen with a simple left-click.
- **Automatic High-Resolution Album Art:** Bypasses low-resolution browser MPRIS thumbnails (`96x96` / `120x120`) by dynamically fetching `1000x1000` original studio album covers via the iTunes Search API (with automatic caching and MPRIS fallback).
- **Real-Time Synced Lyrics:** Streams time-synced lyrics directly from `sptlrx` via MPRIS.

---

## Dependencies

Ensure the following packages are installed on your system:

- **`quickshell`** (UI framework & Wayland layer-shell integration)
- **`sptlrx`** (Synced lyrics provider in pipe mode)
- **`inter-font`** (Default font used by the widget; can be changed in `shell.qml`)

*Arch Linux / CachyOS installation example:*
```bash
paru -S quickshell-git sptlrx-bin inter-font
```

---

## File Structure

Copy the configuration files to their respective directories inside `~/.config`:

```text
~/.config/
├── quickshell/
│   └── lyrics-widget/
│       └── shell.qml
└── sptlrx/
    └── config.yaml
```

---

## Usage & Commands

You can run these commands directly in your terminal or bind them to any keyboard shortcut in your window manager / compositor (Hyprland, Sway, Niri, River, etc.):

### 1. Start / Stop Toggle
Starts the widget in daemon mode if it is not running, or completely quits the process if it is already active:
```bash
sh -c 'quickshell ipc -c lyrics-widget call lyrics quit || quickshell -c lyrics-widget -d'
```
### 2. Toggle Drag / Reposition Mode
Unlocks the widget (indicated by a thin white border) so you can drag it around using the **Left Mouse Button**. Right-clicking the widget, clicking anywhere outside it, or running the command again locks it back into click-through mode:
```bash
quickshell ipc -c lyrics-widget call lyrics toggle
```

---

## Browser & Media Player Configuration

By default, the widget prioritizes **Vivaldi**, **Chromium**, and **Floorp**. If you use another browser (e.g., Brave, Zen, Firefox, Chrome) or a dedicated desktop client (e.g., `youtube-music-bin`, `spotify`), update the following two files:

> **Tip for Browser Users:** Chromium-based browsers (Vivaldi, Brave, Chromium, Chrome) and the dedicated `youtube-music-bin` desktop app update MPRIS track positions continuously in the background and are strongly recommended for smooth lyric syncing.

### Step 1: Add your player to `~/.config/sptlrx/config.yaml`
Add your media player or browser's MPRIS name to the `players` list under the `mpris` section:
mpris:
  players:
    - "vivaldi.instance30468"
    - "firefox"
    - "chromium"
    - "youtube-music"
    - "YoutubeMusic"

#### How to find your player's MPRIS name

While a song or video is playing in your browser or media client, run one of the following commands in your terminal:

```bash
# Method 1: Using systemd's busctl (pre-installed on most Linux distros)
busctl --user list | grep -o 'org.mpris.MediaPlayer2.[^ ]*' | sed 's/org.mpris.MediaPlayer2.//'

# Method 2: Using playerctl (if installed)
playerctl -l
```

> **Note on `.instance` numbers:** Browsers often append a dynamic process/instance ID to their MPRIS name
(e.g., `vivaldi.instance30468` or `firefox.instance_1_117`). Because these numbers change every time you restart the browser,
it is recommended to also include the base name (such as `"vivaldi"`, `"firefox"`, or `"chromium"`) in `config.yaml`.
Note that Firefox-based browsers (Floorp, Zen, LibreWolf) usually register under the `firefox` MPRIS prefix. 

### Step 2 (Optional): Fine-tune player priority in `shell.qml`

> **Note:** **This step is strictly optional.** The widget will automatically pick up your active media player out of the box without any code changes. You only need to edit this section if you frequently have multiple media sources running at the same time (e.g., a paused video tab in your main browser while streaming music in another player) and want to grant explicit priority to your preferred player.

To change player precedence, locate the `activePlayer` property inside `~/.config/quickshell/lyrics-widget/shell.qml` and add your player's keyword (in lowercase) to the filter checks:

```qml
var isBrowser = (id.indexOf("vivaldi") !== -1 || bus.indexOf("vivaldi") !== -1 ||
                 id.indexOf("chromium") !== -1 || bus.indexOf("chromium") !== -1 ||
                 id.indexOf("brave") !== -1 || bus.indexOf("brave") !== -1 ||
                 id.indexOf("firefox") !== -1 || bus.indexOf("firefox") !== -1 ||
                 id.indexOf("spotify") !== -1 || bus.indexOf("spotify") !== -1 ||
                 id.indexOf("floorp") !== -1 || bus.indexOf("floorp") !== -1)
```
*(If you make changes here, apply the same keywords to the fallback loop directly below it inside `activePlayer`.)*
*(Remember to also add the same check to the fallback `for` loop immediately below it in `activePlayer`.)*

---

## Customizing Appearance

All visual styling is controlled via properties at the top of the `ClippingRectangle { id: root ... }` block in `~/.config/quickshell/lyrics-widget/shell.qml`. Quickshell hot-reloads changes automatically as soon as you save the file.

### 1. Widget Size & Shape
Modify `width`, `height`, and `radius` inside `ClippingRectangle`:
```qml
ClippingRectangle {
    id: root
    width: 325      // Total widget width in pixels
    height: 260     // Total widget height in pixels
    radius: 24      // Corner roundness (set to 0 for sharp rectangular corners)
```

### 2. Opacity & Transparency
Adjust how see-through the widget and its layers are (`0.0` = completely invisible, `1.0` = completely solid):
```qml
property real widgetOpacity: 0.88        // Master opacity of the entire widget
property real coverArtOpacity: 0.65      // Opacity of the album art background (lower = more see-through)
property real backgroundDimOpacity: 0.30 // Darkening tint layer over the album art
property real innerBoxOpacity: 0.55      // Opacity of the centered dark lyrics container
```

### 3. Inner Lyrics Box Proportions
Control the size and rounding of the inner dark box that holds the lyrics text:
```qml
property real innerBoxWidthRatio: 0.92   // Width relative to the main widget (0.92 = 92%)
property real innerBoxHeightRatio: 0.48  // Height relative to the main widget (0.48 = 48%)
property int innerBoxPadding: 12         // Inner text margin in pixels
property real innerBoxRadius: 12         // Corner roundness of the inner box
```

### 4. Typography (Font, Size & Color)
Customize how the lyrics text is rendered:
```qml
property int lyricsFontSize: 20               // Font size in pixels
property string lyricsFontFamily: "Inter"     // Any installed system font (e.g., "JetBrainsMono Nerd Font", "Roboto")
property int lyricsFontWeight: Font.Bold      // Font.Normal, Font.Medium, Font.DemiBold, Font.Bold
property color lyricsTextColor: "#ffffff"     // Hex color code for the lyrics text
```

### 5. Default Screen Position
By default, the widget spawns at the bottom-right corner (`60px` margin). To change the initial spawn position, edit the `onWidthChanged` block near the top of `shell.qml`:
```qml
onWidthChanged: {
    if (!positionInitialized && width > 0 && height > 0) {
        root.x = width - root.width - 60   // X coordinate (e.g., use 60 for left side)
        root.y = height - root.height - 60 // Y coordinate (e.g., use 60 for top side)
        positionInitialized = true
    }
}
```
