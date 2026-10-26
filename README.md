# MacCacheCleaner

A small native macOS app for finding out where your disk space went and clearing it out.

<img src="Resources/AppIcon-1024.png" alt="MacCacheCleaner icon" width="128">

## Features

### Disk Usage
- WinDirStat/WizTree-style expandable folder tree with total sizes for every folder
- **% of Parent** bar, file counts and modification dates
- Sort by name, size, file count or date (applies at every level of the tree)
- Right-click any item: **Reveal in Finder**, **Open**, **Copy Path**, **Move to Trash**, **Delete Permanently**
- Totals update instantly after a delete, without rescanning
- iCloud Drive is skipped by default (it's slow to scan); check **Include iCloud Drive** to add it
- Doesn't cross into other mounted volumes, so scanning `/` won't double count

### Cache Cleaner
- Lists 12 common macOS cache and temp locations (User Caches, System Temp, Logs, Crash Reports, Xcode Derived Data, Homebrew Cache, Trash, Downloads, Safari Cache, and more)
- Calculate sizes for all locations or one at a time, color-coded by size
- Open any location in Finder, or clear its contents (with confirmation)

### Large Files
- Scan any folder for files over a minimum size (50 MB to 5 GB)
- Live results while scanning, with a Stop button
- Sortable columns: name, size, modified date
- Reveal in Finder or delete each file (with confirmation)

### Permissions setup
On first launch, a short walkthrough explains why the app needs to read protected folders, links to **Full Disk Access** in System Settings, and requests Desktop, Documents, Downloads and iCloud Drive access up front, so a scan can run unattended without stopping for permission pop-ups. You can reopen it any time from **MacCacheCleaner → Permissions…**.

## Install

1. Download `MacCacheCleaner-<version>.dmg` from [Releases](../../releases).
2. Open the DMG and drag **MacCacheCleaner** into **Applications**.
3. The app isn't notarized by Apple, so the first time you open it macOS will block it. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the MacCacheCleaner message.

Requires macOS 13 or later on Apple Silicon.

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh      # builds build/MacCacheCleaner.app
./package.sh    # builds and packages dist/MacCacheCleaner-<version>.dmg
```

The version number comes from `CFBundleShortVersionString` in `Info.plist`.

> **Note:** builds are ad-hoc signed, and macOS ties privacy permissions to an app's signature, so each new build has to be granted permissions again. The permissions walkthrough reappears automatically after a rebuild.
