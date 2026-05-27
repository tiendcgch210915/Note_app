# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app (Dart SDK `^3.8.1`), package name `todonote`. As of this writing, `lib/main.dart` still contains the **default Flutter counter scaffold** — no todo/note domain code exists yet. Do not assume any architecture beyond what's actually in the files.

## Commands

| Purpose | Command |
|---|---|
| Install deps | `flutter pub get` |
| Run app (dev, hot reload) | `flutter run` |
| Run on a specific device | `flutter run -d <device_id>` (list with `flutter devices`) |
| Run all tests | `flutter test` |
| Run a single test file | `flutter test test/widget_test.dart` |
| Run a single test by name | `flutter test --plain-name "Counter increments smoke test"` |
| Static analysis / lint | `flutter analyze` |
| Format Dart sources | `dart format .` |
| Clean build artifacts | `flutter clean` |
| Build release APK | `flutter build apk` |

No Makefile or custom scripts — everything runs through the Flutter CLI.

## Architecture (current state)

- **Entry point**: [lib/main.dart](lib/main.dart) — single file, `MyApp` (root `MaterialApp`) → `MyHomePage` (StatefulWidget with a counter).
- **State management**: plain `setState` only. No Provider, Riverpod, Bloc, GetX, etc. wired up — if a feature needs cross-widget state, the choice is still open.
- **Tests**: [test/widget_test.dart](test/widget_test.dart) — single widget smoke test for the counter.
- **Platforms**: `android/` is checked in (Gradle Kotlin DSL). No `ios/` folder in this checkout — run `flutter create --platforms=ios .` to add iOS support.

## Lint baseline

`analysis_options.yaml` extends `package:flutter_lints/flutter.yaml` with no custom rules or overrides. Run `flutter analyze` before declaring work complete.
