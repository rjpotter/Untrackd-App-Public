# Untrackd
### GPS Activity Tracking for Skiers, Hikers & Cyclists

> **Status:** Completed — pending App Store release

<!-- 📸 HERO IMAGE: A full-width screenshot of the app's main screen or a composite showing 2-3 key screens side by side. Ideal: track playback or the 3D map. Aim for a 16:9 or wider banner crop. -->
![Untrackd Hero](assets/hero.png)

---

## Overview

Untrackd is a native iOS app built for outdoor athletes who want more than a step counter. It records GPS tracks with high fidelity, calculates detailed performance stats, and gives you a rich set of tools to explore, share, and plan your time outdoors — whether you're on skis, trails, or a bike.

Built entirely solo in Swift/SwiftUI, from GPS engine to social layer.

---

## Features

### 📍 GPS Track Recording
Real-time activity tracking with a custom GPS filtering pipeline that eliminates glitch spikes — no more 100 mph readings from a bad satellite fix. Calculates max speed, vertical gain/loss, distance, and time on the fly.

<!-- 📸 SCREENSHOT: The live recording screen showing the map with a track being drawn + the live stats overlay (speed, vertical, time). Portrait iPhone screenshot. -->
![Track Recording](assets/recording.png)

---

### 📊 Detailed Stats & History
Per-track stats are cached locally and synced to Firebase. Lifetime stats aggregate across every session you've ever recorded — top speed, total vertical, best days, streaks, and more. Tappable stat cards drill into dedicated detail views.

<!-- 📸 SCREENSHOT: The stats/profile screen showing lifetime stat cards (top speed, total vertical, etc.). Could also be a side-by-side of the stat card and the detail drill-down view. -->
![Stats Overview](assets/stats.png)

---

### 🗺️ 3D Interactive Map with Route Builder
A Mapbox-powered 3D map lets you visualize saved routes as colored overlays with elevation profiles. Tap any route to open an inspector with a scrub bar, stats grid, and color picker. Build new routes by panning the map and dropping waypoints with a crosshair — no tap-target fighting.

<!-- 📸 SCREENSHOT: The 3D map view with a route drawn on it, ideally with the route inspector panel open at the bottom showing the elevation profile chart. -->
![3D Map](assets/map.png)

---

### 🎬 Track Playback & Visualization
Recorded tracks play back as animated overlays with four color modes: Normal, Speed gradient, Activity type, and Uphill/Downhill. A scrub bar lets you move through the track frame by frame. Chairlift segments are detected automatically.

<!-- 📸 SCREENSHOT OR GIF: The track playback screen with the color mode active (Speed gradient looks great) and the scrub bar visible at the bottom. A GIF of the animation playing would be ideal here. -->
![Track Playback](assets/playback.png)

---

### 📤 Track Export
Export your tracks as shareable cards — either a map snapshot with stats overlaid, or a full photo background with a draggable track sticker. Supports Instagram-compatible canvas sizes.

<!-- 📸 SCREENSHOT: The export screen showing a finished card — ideally the photo background + track sticker version. Could show two export styles side by side. -->
![Export](assets/export.png)

---

### 🥽 AR Track Viewer *(Experimental)*
View a saved route overlaid on the real world through your camera using ARKit. GPS coordinates are converted to local ENU space and rendered as a 3D tube on the ground, anchored to your real-world position — like a Waze overlay for the trail ahead.

<!-- 📸 SCREENSHOT: The AR view in action outdoors, showing the orange tube path overlaid on a real trail or slope. If you don't have an outdoor shot yet, a description placeholder is fine. -->
![AR Viewer](assets/ar.png)

---

### 👥 Social Layer
Follow friends, view their tracks and stats, and compare performances. Friend profiles load from Firebase with full stat breakdowns. Activity types (ski, hike, bike) tag each track and filter into season breakdowns.

<!-- 📸 SCREENSHOT: A friend's profile view showing their stats and track history, or the friends list view. -->
![Social](assets/social.png)

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| UI Framework | SwiftUI |
| Maps | Mapbox Maps SDK v11 |
| Charts | Swift Charts |
| AR | ARKit + SceneKit |
| Backend | Firebase (Auth, Firestore) |
| GPS Processing | Custom filtering pipeline |
| Dependency Management | CocoaPods |
| Distribution | TestFlight → App Store (pending) |

---

## Architecture Highlights

- **Stats Cache** — Per-track and lifetime stats are cached locally in a typed `Codable` struct system, independent of Firebase. Cache rebuilds without wiping activity assignments. Syncs to Firebase on update via `NotificationCenter`.
- **GPS Glitch Filtering** — A 7-point sliding window compares speed to/from each candidate point against the surrounding context. Spikes that aren't corroborated by neighboring points are removed before stats are calculated.
- **Chairlift Detection** — Segments are classified as lifts using a path straightness score over a sliding window, making it robust to gondolas and terrain-variable lifts where elevation alone fails.
- **Mapbox Architecture** — The map fills the full ZStack as a base layer with UI overlaid on top. Invisible tap layers use `lineOpacity: 0.001` (not `UIColor.clear`) for reliable hit detection. Route previews update via `updateGeoJSONSource` on a `CircleLayer`-backed source to avoid flickering.
- **Export Rendering** — Canvas is rendered at preview dimensions and scaled up, keeping sticker positions and crop alignment correct across all export size presets.

---

## Project Status

The app is feature-complete and currently in TestFlight. App Store release is pending LLC formation.

This repository is intentionally partial — core business logic and the full source are kept private. This repo is a curated window into the architecture and feature set.

---

## Contact

Ryan Potter · [ryanjpotter1@gmail.com](mailto:ryanjpotter1@gmail.com)
