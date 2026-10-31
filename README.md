# NanoSwitch

**See every window. Switch in one move.**

macOS's built-in Cmd+Tab cycles through apps.
NanoSwitch shows a thumbnail grid of every **window** — so you jump directly to the exact one you need.

![NanoSwitch](https://github.com/user-attachments/assets/a96eb9e6-ea74-4990-b048-ecaf70e0b275)

---

## How it works

Hold `Cmd+Tab` → thumbnail grid appears → navigate with Tab or arrow keys → release Cmd to switch.

No new shortcuts to learn. No configuration needed. Just a better Cmd+Tab.

---

## Features

- **Window-level switching** — see all open windows, not just apps
- **Live thumbnail previews** — see the content before you switch
- **Current-Space focus** — shows the windows on your current desktop. When your current Space has fewer than two windows, `Cmd+Tab` falls through to the built-in switcher so you can still reach apps on other Spaces
- **Instant display** — icons appear immediately, thumbnails load in the background
- **Lightweight** — lives in your menu bar, runs silently, launches at login
- **Close windows directly** — hover any thumbnail and click ×, or press `W`

---

## Requirements

- macOS 14.6 or later
- **Accessibility** permission — required to intercept Cmd+Tab
- **Screen Recording** permission — required for the thumbnail previews that make NanoSwitch worth using

Both permissions are requested on first launch and can be granted without restarting the app.

> Without Screen Recording, NanoSwitch can only show plain app icons — which offers little over the built-in Cmd+Tab. Grant it to get the live window previews that are the whole point of the app.

---

## Installation

1. Download `NanoSwitch.zip` from [Releases](../../releases/latest)
2. Unzip and move `NanoSwitch.app` to `/Applications/` (the system Applications folder)
   > ⚠️ Do **not** place it in `~/Applications/` — Screen Recording thumbnails will silently fail if the app runs from your user Applications folder.
3. Launch the app and grant the two permissions when prompted

**If macOS blocks the app on first launch:**
Right-click `NanoSwitch.app` → **Open**, then confirm. (Or open **System Settings → Privacy & Security** and click **Open Anyway**.)

---

## Usage

| Action | Key |
|--------|-----|
| Open switcher / Next window | `Cmd+Tab` |
| Previous window | `Cmd+Shift+Tab` |
| Navigate | Arrow keys |
| Switch | Release Cmd |
| Cancel | `Escape` |
| Close selected window | `W` |

Toggle **Launch at Login** and open **About / Help** from the menu-bar icon.

---

## Troubleshooting

**Thumbnails not showing / only app icons appear**

First, grant **Screen Recording** in **System Settings → Privacy & Security → Screen Recording**.
If it's already granted, make sure `NanoSwitch.app` is in `/Applications/` (not `~/Applications/`) — Screen Recording thumbnails silently fail when the app runs from a user Applications folder.

**Cmd+Tab isn't being intercepted**

Open the menu-bar icon. If you see a "Cmd+Tab を横取りできていません" warning, re-grant **Accessibility** in **System Settings → Privacy & Security → Accessibility** (remove and re-add NanoSwitch), then relaunch.

**App blocked by macOS Gatekeeper**

Right-click `NanoSwitch.app` → **Open**, or open **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Support

NanoSwitch is free and ad-free.

If it improves your workflow → [Buy Me a Coffee](https://buymeacoffee.com/lifedesignstudio)

---

*Made by [Life Design Studio](https://github.com/LifeDesignStudio)*
