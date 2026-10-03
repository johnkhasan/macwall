# AeroWall Architecture and Rules

## Overview
AeroWall is a native macOS live wallpaper app designed to play videos on the desktop background across multiple monitors.

## Core Rules
- **Platform**: macOS 14 Sonoma or newer (Apple Silicon optimized).
- **Frameworks**: Native Swift, SwiftUI, AppKit, AVFoundation.
- **App Sandbox**: MUST BE DISABLED. We run outside the Mac App Store to allow manipulating desktop window levels.
- **Dock**: Do not show in Dock (`LSUIElement = YES`). The app runs in the menu bar.
- **Code Style**: Swift 5.10+, declarative where possible.

## Project Structure
- `App/`: `AppDelegate`, `MenuBarExtra`, Entry Point.
- `Engine/`: `WallpaperWindow`, `PlayerController`, `ScreenManager`.
- `Library/`: `VideoImporter`, `ThumbnailGenerator`, `HEVCConverter`.
- `Scheduling/`: `PlaylistManager`, `AppearanceObserver`.
- `Power/`: `PauseController` (occlusion, battery, sleep, thermal).
- `Effects/`: `WeatherService`, `ParticleScene`.
- `Settings/`: SwiftUI settings UI.
