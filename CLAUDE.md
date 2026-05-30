# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Get dependencies**: `flutter pub get`
- **Analyze (lint)**: `flutter analyze`
- **Run all tests**: `flutter test`
- **Run single test**: `flutter test test/path/to/test.dart`
- **Build Android**: `flutter build apk --release`
- **Build iOS**: `flutter build ios --release --no-codesign`
- **Build Linux**: `flutter build linux --release`
- **Build macOS**: `flutter build macos --release`
- **Build Windows**: `flutter build windows --release`
- **Build Debian package**: `python3 debian/build.py` (Linux only)
- **Build Arch package**: `dart run flutter_to_arch` (Linux only)

## Project Overview

**Pica Comic** (v4.2.11) is a cross-platform Flutter comic reader aggregating 6 built-in comic sources with JS-based custom source support. SDK: Dart `>=3.3.0`.

## Architecture

### Layered Structure

```
UI (pages/ + components/)
  ↕ Source Abstraction (comic_source/)
    ↕ Foundation Services (foundation/ + network/ + tools/)
      ↕ Persistence (SQLite + SharedPreferences + JSON files)
```

### Key Patterns

- **State management**: Lightweight custom controller pattern (`foundation/state_controller.dart`). `StateController` abstract class with `StateBuilder<T>` widget for reactive updates.
- **Navigation**: Custom `AppPageRoute` (slide transitions + iOS back gesture). Navigate via `App.to()`, `App.off()`, `App.back()`.
- **Networking**: Dio-based HTTP client factory (`logDio()`) with automatic retry, SNI bypass, and cookie interceptors. Source-specific network modules under `network/{source}_network/`.
- **Comic Source abstraction**: `ComicSource` class in `comic_source/comic_source.dart` defines a pluggable interface. All sources implement optional capabilities (login, favorites, categories, explore, search, comments). Custom JS sources loaded via QuickJS engine.
- **Results**: Generic `Res<T>` result type (`network/res.dart`) with `data`, `errorMessage`, `success`/`error` for all network operations.
- **Global singletons** (in `base.dart`): `appdata` (Appdata — ~90 positional string settings), `downloadManager`, `notifications`.
- **Settings**: Indexed string list persisted via SharedPreferences + JSON file fallback. Typed getters in `_Settings` class.
- **Image loading**: Central `ImageManager` with per-source image loaders (Picacg, EH, JM descrambling, Hitomi GG-token, Custom JS).
- **Adaptive layout**: 3 breakpoints — phone (<600px, bottom nav), tablet (600–1400px, collapsed sidebar), desktop (>1400px, expanded sidebar).

### Initialization Flow

`main()` → `init()` (in `init.dart`) runs in strict order:
1. App paths → Logging → Settings load → Cookie jar → Proxy → Cache cleaner
2. JS engine → Comic source loading (built-in + custom .js files)
3. Parallel: DownloadManager init, each source's network init, LocalFavorites, History, Translation

### Directory Layout

```
lib/
  base.dart                     # Global singletons
  init.dart                     # Async boot sequence
  main.dart                     # Entry point, theme, routing
  comic_source/                 # ComicSource abstraction + 6 built-in sources + JS parser
  components/                   # Reusable widgets (~25 files)
  foundation/                   # Services: App utils, state mgmt, image mgmt, cache, history, favorites, logging, JS engine
  network/                      # Dio config, proxy, download manager, WebDAV sync, per-source network modules
  pages/                        # App screens: main page, reader, settings, per-source pages, favorites
  tools/                        # Utilities: i18n, extensions, deep links, background service, notifications, PDF export, tag translation
test/
  widget_test.dart              # Placeholder test file
```

### Supported Comic Sources

- **picacg**: Encrypted API, login, daily check-in
- **ehentai**: HTML scraping, cookie auth, multi-folder favorites
- **jm** (禁漫天堂): Pixel descrambling, weekly recommendations
- **hitomi**: GG token image URLs, language filters
- **htmanga** (绅士漫画): HTML scraping, multi-category
- **nhentai**: REST API, tag suggestions
- **Custom JS sources**: Run via QuickJS with Network/Convert/HtmlDocument APIs (see `doc/comic_source.md`)

### Reader Subsystem (`lib/pages/reader/`)

Feature-rich reader supporting 4 reading modes: LTR, RTL, TTB continuous, TTB paged. Includes touch gesture handling, toolbar, settings, episode selector, and per-source image loading.

### Persistence

- **Settings**: SharedPreferences + JSON file backup (`appdata.settings` string list)
- **Cookies**: SQLite via `SingleInstanceCookieJar`
- **Downloads**: SQLite (`download.db`) + JSON queue (`newDownload.json`)
- **History**: SQLite (`history.db`)
- **Local Favorites**: SQLite (per-folder tables)
- **Image Cache**: SQLite-backed disk cache with SHA256-hashed paths and LRU eviction
- **WebDAV sync**: Cross-device sync for settings, favorites, history
