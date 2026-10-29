<p align="center">
  <img src="assets/banner.svg" alt="ReaLauncher — a project launcher for REAPER" width="100%">
</p>

<p align="center">
  <b>English</b> · <a href="README.es.md">Español</a> · <a href="https://djenttleman.github.io/realauncher/">Website</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-0B0B0D?style=flat-square&labelColor=1a1a20" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-8660E8?style=flat-square&labelColor=1a1a20" alt="Swift">
  <img src="https://img.shields.io/badge/no%20electron-yes%20please-1ED760?style=flat-square&labelColor=1a1a20" alt="No Electron">
  <img src="https://img.shields.io/badge/version-1.0.0-4377FF?style=flat-square&labelColor=1a1a20" alt="v1.0.0">
  <img src="https://img.shields.io/badge/license-MIT-1ED760?style=flat-square&labelColor=1a1a20" alt="MIT">
</p>

<p align="center">
  <i>Made by humans and AI, for humans with feelings.</i>
</p>

---

## Why this exists

Honestly? I always found REAPER's project launcher… poor.

I know REAPER isn't exactly a design showcase, and I'm fine with that — the thing is a beast and it earns its looks. But the launcher was definitely the weak spot, especially coming from other DAWs like Studio One, where at least the thing feels a little more polished: a proper list, something that tells you *where* you left things.

So I built my own, with AI's help. I used **DeepSeek V4.1 Flash** end to end — design, code, the weird parts too.

It started as a tool for my own live shows. Then it grew folders, tags, backups, an inspector and a lot of opinions about spacing. Now it's here, in case your `Choose Project` window also makes you a little sad.

## Features

| | |
|---|---|
| 🌗 **Dark, light and five color schemes** | Reapertips, ReaSet Pro, Cyan, Amber and Rose, all with a real light mode. Not an afterthought. |
| 🗂 **Virtual folders and tags** | Group your projects however you think about them — by show, by client, by mood. It never moves a single file. |
| 🔎 **Instant search and filters** | Type and filter by type, folder, pinned or archived. `⌘K` and you're typing. |
| 🧭 **Project inspector** | Regions, tracks, tempo, size and the last time you touched it, read straight from the `.rpp`. |
| 🗃 **Nested backups** | Every `.rpp-bak` sitting next to your project shows up in a fold-out row. Open it or reveal it. |
| 🧩 **Create from templates** | Empty, recording, editing, mixing, mastering or a live show — it writes the right file in the right place. |
| 📊 **Session stats** | Hours with REAPER open and hours actually recording, accumulated by a quiet Lua script. |
| 🖱 **Its own right-click menus** | Rename, recolor and re-icon folders; pin, archive, move or trash projects. No native WebKit menu, no text selection. |
| 🔒 **Update-proof** | The Lua scripts live in your REAPER resource folder and register themselves in the Action List, so a REAPER update doesn't break them. |
| ⚡ **Fast and quiet** | Native window, no Electron, opens in ~0.4 s with no white flash and no visible redraw. |
| ⌘Q **Quits everything** | One keystroke and both the launcher and REAPER are gone. |

## Screenshots

<p align="center">
  <img src="assets/en/screenshot-dark.png" alt="ReaLauncher, dark theme" width="100%">
</p>

<p align="center">
  <img src="assets/en/screenshot-light.png" alt="ReaLauncher, light theme" width="100%">
</p>

<p align="center">
  <img src="assets/en/menus.png" alt="Right-click menus for projects and folders" width="100%">
</p>

<p align="center">
  <img src="assets/en/modals.png" alt="New project and folder editor" width="72%">
</p>

<sub>The demo data in those shots is invented; the layout, the spacing and the little details are what you actually get.</sub>

## Install

**One command** — clones, builds and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/djenttleman/realauncher/main/bootstrap.sh | bash
```

**Or step by step**, if you like to see what runs on your machine:

```bash
git clone https://github.com/djenttleman/realauncher.git ~/dev/realauncher
cd ~/dev/realauncher
./install.sh
```

Requirements: **macOS 13+**, **Xcode Command Line Tools** (`swiftc`) and **REAPER 7**.

The installer builds the app into `~/Applications/ReaLauncher.app`, copies the two Lua scripts into your REAPER resource folder, hooks them into `__startup.lua` and sets `loadlastproj=19` so REAPER stops showing its own dialog. It backs up the two files it edits, and nothing else in your REAPER config is touched.

## How it works

It's two pieces and a trick. The app is a small native macOS window — AppKit plus a WebView, no Electron, no Node, nothing downloaded at runtime. On the REAPER side there are two Lua scripts: one opens the launcher at startup, the other quietly accumulates your session hours. They live in your resource path and register themselves as an action, so a REAPER update doesn't touch them. The app reads the header of each `.rpp` to pull out regions, tracks and tempo, caches what it finds keyed by modification date and size, and renders everything in its own interface. `loadlastproj=19` tells REAPER to start with a new project instead of asking which one — that's what makes the custom window the first thing you see.

## Good to know

- **macOS only.** It's built with AppKit; porting it is a different project.
- **Nothing is moved or renamed** behind your back. Folders, tags and pins live in `~/Library/Application Support/ReaLauncher/library.json`.
- **Deleting a project** from the inspector sends the `.rpp` to the Trash and removes it from the library. It asks first.
- **The first scan asks for file access** on folders like Documents or Downloads — the app only reads `.rpp` headers.
- **Uninstall**: `./install.sh --revert` restores REAPER's own launcher, then delete `~/Applications/ReaLauncher.app` and `~/Library/Application Support/ReaLauncher`.

## Credits

Built by **[@djenttleman](https://github.com/djenttleman)** — live engineer, Chile — with **DeepSeek V4.1 Flash** doing a lot of the typing. The visual language borrows the ReaSet Pro design kit; the palette leans on the Reapertips theme.

If it saves you ten seconds every time you open a project, it did its job.

<p align="center"><sub>Made by humans and AI, for humans with feelings.</sub></p>

---

<sub>Technical notes, architecture and measured startup numbers: [DEVELOPMENT.md](DEVELOPMENT.md).</sub>
