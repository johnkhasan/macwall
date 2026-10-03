# AeroWall 🌬️

AeroWall is a native macOS live wallpaper application built with Swift and AppKit. It allows you to play local video files directly on your desktop background, supporting multiple monitors, smart pausing for battery/performance, and customizable playlists.

## Features
- **Native & Lightweight:** Written in Swift using AppKit and AVFoundation. Uses hardware-accelerated decoding (HEVC).
- **Multi-Monitor Support:** Displays wallpapers across all connected screens seamlessly.
- **Smart Pause:** Automatically pauses video playback when windows cover the screen, when running on battery, or under thermal pressure.
- **Interactive Effects:** Overlay particle effects like rain or snow that react to mouse movements.
- **Playlists:** Rotate videos automatically with crossfade transitions.
- **Lock Screen Integration:** Automatically creates static snapshots of your live wallpaper to display on the macOS lock screen.

## Installation
Since AeroWall manipulates the desktop window level, it cannot be distributed via the Mac App Store.

1. Download the latest `.dmg` from the [Releases](https://github.com/your-username/AeroWall/releases) page.
2. Drag and drop `AeroWall.app` into your `Applications` folder.
3. Open `AeroWall`.

### Note on Gatekeeper
If you see an "App cannot be opened" warning (Gatekeeper), do the following:
- Go to **System Settings > Privacy & Security** and click **Open Anyway**.
- Alternatively, run this in Terminal: `xattr -dr com.apple.quarantine /Applications/AeroWall.app`

## Usage
Click the **Play** icon (`play.tv`) in the macOS Menu Bar to open settings. 
Drag and drop your favorite `.mp4` or `.mov` videos into the Library to add them. 

*Sample videos can be downloaded from free stock sites like [Pexels](https://www.pexels.com/videos/) or [Coverr](https://coverr.co/).*

## Development
See [CLAUDE.md](CLAUDE.md) for architectural guidelines and rules for AI generation.
