# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`todonote` is a Flutter productivity app (Dart SDK `^3.8.1`) combining todos (Eisenhower matrix, frog task, subtasks, recurrence, habit-stacking), local-first notes (Quill rich text, Cornell layout, tags/links), habits, checklists (categories/templates/runs), a dashboard, and a calendar — all behind JWT auth, backed by a REST API with an offline-capable local SQLite store and a sync engine. This is not a scaffold; it's a substantial multi-module app.

Package: `todonote`. Platforms in this checkout: **Android only** (`android/`, Gradle Kotlin DSL). No `ios/`, `web/`, `windows/`, `macos/`, or `linux/` folders — run `flutter create --platforms=<name> .` to add one.

Two other docs in the repo root go deeper than this file:
- [AGENTS.md](AGENTS.md) — the authoritative, actively-maintained architecture reference (Vietnamese). When this file and AGENTS.md disagree, or either disagrees with the source, trust the source code first, then AGENTS.md.
- [MOBILE_SYNC_LOCAL_FIRST_AUDIT.md](MOBILE_SYNC_LOCAL_FIRST_AUDIT.md) — a dated (2026-06-24) historical audit of the sync engine. Useful for the *why* behind sync design decisions, but some details (e.g. the backend URL it lists) are stale — prefer [lib/data/api_config.dart](lib/data/api_config.dart) for current config.

[README.md](README.md) is still the default `flutter create` boilerplate and has no project-specific info.

## Commands

| Purpose | Command |
|---|---|
| Install deps | `flutter pub get` |
| Regenerate Drift code (after editing tables/DAOs/database.dart) | `dart run build_runner build --delete-conflicting-outputs` |
| Run app (dev, hot reload) | `flutter run` |
| Run on a specific device | `flutter run -d <device_id>` (list with `flutter devices`) |
| Run all tests | `flutter test` |
| Run a single test file | `flutter test test/sync_payload_test.dart` |
| Run a single test by name | `flutter test --plain-name "<test description>"` |
| Static analysis / lint | `flutter analyze` |
| Format Dart sources | `dart format .` |
| Clean build artifacts | `flutter clean` |
| Build release APK | `flutter build apk` |

No Makefile or custom scripts — everything runs through the Flutter/Dart CLI. Before handing off a change: `dart format .`, `flutter analyze`, `flutter test`.

## Architecture

### Bootstrap

[lib/main.dart](lib/main.dart) just calls `runApp(const MyApp())`. All startup logic lives in [lib/app.dart](lib/app.dart)'s `_MyAppState._bootstrap()`:

1. Hydrate the auth token/user cache (`AuthStorage.instance.init()`).
2. Open the Drift DB singleton (`AppDatabase.instance`).
3. Best-effort health check against the backend.
4. Decide `LoginScreen` vs `HomeShell` based on `AuthRepository.instance.isAuthenticated()`.
5. Start `ConnectivitySync` (syncs on reconnect) and register a post-pull repair hook for recurrence.
6. Listen for a global 401 signal (`needsReLoginNotifier`) that forces back to `LoginScreen`.
7. Kick off an initial `SyncWorker.instance.sync()` if already authenticated; also re-syncs on app resume.

### State management

Plain `StatefulWidget` + `setState`, repository singletons, and `ValueNotifier` for small global signals (theme via `AppThemeController`/`AppThemeScope`, `sync_status_notifier.dart`, `needsReLoginNotifier`). No Provider/Riverpod/Bloc/GetX is wired up — that's a deliberate convention, not an oversight; don't introduce a state management package without a clear, large-scope reason.

### Directory layout (`lib/`)

- `data/` — repositories (one per domain, e.g. `todos_repository.dart`, `notes_repository.dart`), the two HTTP clients, and `local/` (Drift database, tables, DAOs, model converters).
- `models/` — domain models with `fromJson`/`toJson`, mapping backend snake_case to Dart camelCase.
- `screens/` — UI grouped by feature (`auth/`, `todos/`, `notes/`, `habits/`, `checklists/`, `calendar/`, `dashboard/`, `settings/`, `shell/`).
- `sync/` — `sync_worker.dart`, `sync_payload.dart`, `connectivity_sync.dart`, `sync_status_notifier.dart`.
- `theme/`, `utils/`, `widgets/` — shared styling, helpers (date/json/uuid/recurrence), and reusable widgets. Prefer existing helpers in `utils/json_utils.dart`, `utils/date_utils.dart`, `utils/uuid_utils.dart` over ad hoc parsing/ID generation.

### Networking

Two HTTP clients share config from [lib/data/api_config.dart](lib/data/api_config.dart):

- [lib/data/api_client.dart](lib/data/api_client.dart) — `package:http`, used by the primary domain repositories.
- [lib/data/remote/api_client_dio.dart](lib/data/remote/api_client_dio.dart) — Dio, used by `SyncWorker` and an auxiliary auth path; its interceptor is what raises the global 401 signal.

Default backend is `https://todosnotes.onrender.com/api/v1` (health at `/health`). Override via `--dart-define=TODO_NOTE_API_BASE_URL=<absolute-api-v1-url>` rather than hard-coding a URL in either client.

### Local database & codegen

Drift/SQLite lives in `lib/data/local/`: `tables.dart` (schema), `database.dart` (table/DAO registration + migrations, currently `schemaVersion = 12`), `dao/` (per-domain CRUD + sync-queue ops), `model_converters.dart` (domain model ↔ Drift companion). `database.g.dart` and `dao/*_dao.g.dart` are **generated — never hand-edit them**; change the source file and run `dart run build_runner build --delete-conflicting-outputs`. Any schema change must bump `schemaVersion` and add a corresponding migration step.

### Sync engine (outbox pattern)

Local writes go to Drift and enqueue an operation in `sync_queue`. `SyncWorker` pushes the authenticated user's queued ops (capped per batch) and then pulls server deltas, applying everything in one Drift transaction before advancing the per-user cursor (`last_synced_at:<userId>`). Sync is triggered by a 2s debounce after a local write, connectivity reconnect, app resume/boot, or a manual sync action.

**Cache-first reads (Todos, Notes, Checklists).** Their screens paint from Drift first (`listLocal` / `list*Local`), then revalidate against REST and re-render when it returns. Keep these rules when touching them: don't `await` the network before there is something to show; stay silent on `ApiException.isRetryable` errors when cached data is on screen; REST-result cache helpers (`_cacheTodos`, `_cache*` in `ChecklistsRepository`) must skip entities that have a pending `sync_queue` op so the server never overwrites unsynced edits; after a REST delete, soft-delete the Drift row too or the cache-first screen shows it again; sync pull notifies `Todo/Note/ChecklistLocalEvents` so open screens re-read Drift. Dashboard, Calendar and Habits are still REST-first.

The app is **not** uniformly offline-first — each repository has its own read/write strategy (REST-first with cache vs. local-first with background push). Don't assume one repository's behavior applies to another; check AGENTS.md's "Offline behavior" section or the repository source before changing sync-sensitive code. If you change an API contract, update in lockstep: the model's `fromJson`, the repository's request body, the Drift converter/DAO, and `sync_payload.dart` — pay particular attention to the exact snake_case field names the backend expects (e.g. `recurrence_*`, `trigger_after_todo_id`, `category_id`, `completed_at`, `content_format`, `body_delta`, `cornell_cue_delta`, `cornell_summary_delta`).

### Push notifications (FCM, Android only — device registration wired to the back-end)

Code lives in `lib/push/`; `lib/firebase_options.dart` + `android/app/google-services.json` come from `flutterfire configure`. `main()` initialises Firebase then `PushNotificationService.init()` (a failure only disables push, it must never block app start). Things that are easy to get wrong:

- **Registration id = FCM token, not FID.** `firebase_messaging 16.7.0` has no `onRegistered()`/`register()`, so [push_registration_service.dart](lib/push/push_registration_service.dart) uses `getToken()` + `onTokenRefresh` and emits `PushRegistrationId(value, kind: token)` on `registrationIds`. Consume it from that stream / `current` only — don't add a second `getToken()` caller. If a newer `firebase_messaging` gains the FID API, add the `firebase_messaging_installation_id_enabled` manifest meta-data and switch the `kind`. The token is printed only under `kDebugMode`.
- **Login/logout are detected through `AuthStorage.instance.authenticated`** (a `ValueListenable<bool>` set by `init`/`saveToken`/`clear`, so the 401 path is covered), not by hooks in the login/settings screens. Sign-in starts registration and asks for the notification permission **once** (only while the status is `notDetermined`, and only after `PushNavigation.appReady`); sign-out stops registration but never calls `deleteToken()` (the FCM token is left alone; the server row is removed via `DELETE /devices`, below).
- **Device registration with the back-end lives in [push_device_registrar.dart](lib/push/push_device_registrar.dart)** (contract in the back-end repo `Todo_Note`: `src/routes/api/v1/devices.ts`). `POST /api/v1/devices` `{registrationId, kind, platform:"android"}` fires on every id emitted by `PushRegistrationService` — which already covers "after login", "token refreshed" and "every app start while logged in" (the server bumps `last_seen_at` per call). Transient failures (offline, timeout, 429, 5xx, `response_parse_error` = Render waking up) retry up to `maxAttempts` with `backoff`, in the background; once exhausted it waits for connectivity to return. 4xx other than 408/425/429 never retry. `DELETE /api/v1/devices` takes the id in a **JSON body** (not the query string — `ApiClient` logs the URL even in release, so never put the id in a URL). Both calls use `PushDevicesApi.requestTimeout` (75 s) via the new optional `timeout:` of `ApiClient.post/delete`; other calls keep no timeout.
- **Logout order matters.** `AuthRepository.logout()` runs `addBeforeLogoutHook` hooks *before* `AuthStorage.clear()`; the registrar's `unregisterCurrent()` issues the `DELETE` synchronously (so `ApiClient` attaches the JWT while it still exists), waits at most `logoutWait` (3 s) and never throws, so offline/slow/failed unregistering can't block logging out. The 401 path can't unregister (no valid JWT); the server moves a registration to whichever user registers it next and prunes dead/stale ones itself. Known residual race: a `POST` already in flight at logout can land after the `DELETE`.
- **Tapping a notification goes through `PushNavigation.handle(PushTarget)`**, never a direct `Navigator.push`. Targets received before `markAppReady()` (cold start: `getInitialMessage` runs before `AuthStorage.init`) wait; targets received while logged out are dropped. Add real FCM `data.type` values in the `switch` of `openPushTarget()` in [push_navigation.dart](lib/push/push_navigation.dart) (types that need an `id` return `false` without one). Android 16.7.0 does **not** call `onMessageOpenedApp` for a tap that cold-starts the app, hence `getInitialMessage()` and `getNotificationAppLaunchDetails()` in `PushNotificationService`.
- **Foreground messages are re-shown as local notifications** (Android doesn't display FCM while the app is open) on channel `general_notifications`, which must match the `default_notification_channel_id` meta-data in `AndroidManifest.xml`. Data-only messages in the foreground are ignored; no `onBackgroundMessage` is registered because system-displayed `notification` messages don't need it.
- Android build requirements this brought in: Java 17, core library desugaring (`desugar_jdk_libs`), `minSdk` ≥ 23 (Firebase), and `res/raw/keep.xml` keeping `@drawable/ic_stat_notification` so R8 doesn't strip the notification icon in release. `flutter_local_notifications 20.x` uses **named** parameters (`initialize(settings:)`, `show(id:, title:, body:, notificationDetails:, payload:)`).

### Notable domain models

- **Notes** — `free` or `cornell` type; rich text stored as Quill Delta (`content_format: plain|quill_delta_v1`) with plain-text mirror fields for legacy/preview; tags, outgoing links, backlinks, and linked todos.
- **Todos** — Eisenhower quadrant, frog task, subtasks, habit-stacking trigger, and recurrence (`recurrence_type`/`recurrence_template_id` define templates vs. instances; completing a recurring todo materializes exactly one next occurrence, cloning its active subtree).
- **Focus session** — the countdown behind a todo's "Bắt đầu" button lives in the app-level singleton [lib/utils/focus_session_controller.dart](lib/utils/focus_session_controller.dart), not in the screen, so it keeps running after the user leaves `TodoFocusScreen` via the Home/Calendar buttons (or system back). The X button never ends the session directly: it asks "Trở lại" (go home, keep running) vs "Hủy bấm giờ" (stop and return to the todo detail page). It is in-memory only (no Drift, no sync) and is cleared on logout/401. While it runs in the background, [lib/widgets/focus_session_banner.dart](lib/widgets/focus_session_banner.dart) renders a bar in `MaterialApp.builder` that takes real layout space (don't turn it into an overlay — it would cover bottom nav/FABs). The controller re-reads the todo from Drift on every `TodoLocalEvents` change (including sync pulls), so don't call `completeLocalFirst` with a todo snapshot taken before the session started. Open the screen through `openTodoFocusScreen()`, never a bare `Navigator.push`.
- **Checklist session & one-thing-at-a-time** — "Bắt đầu" on a checklist creates a run and registers it in [lib/utils/checklist_session_controller.dart](lib/utils/checklist_session_controller.dart), which **counts up** from the run's `startedAt` (wall-clock, in-memory only, cleared on logout/401 via `cancelAllSessions()`). Leaving `RunDetailScreen` with back keeps the run going and shows the same global banner (`FocusSessionBannerHost` renders either kind); only "Hoàn tất" or "Hủy bỏ" (screen X, or the banner stop button which marks the run `abandoned`) ends it. Todos and checklists share [lib/utils/active_session_lock.dart](lib/utils/active_session_lock.dart): at most ONE session app-wide, and both controllers' `start()` return `false` when refused — never reintroduce "replace the running session". Always go through `beginChecklistRun()` / `openChecklistRun()` / `openRunDetail()` / `ensureNoActiveSession()` (in `run_detail_screen.dart` and `active_session_guard.dart`) instead of calling `startRun` or `Navigator.push(RunDetailScreen)` directly; `openRunDetail` sets the "screen open" flag *before* pushing so the banner hides without flicker (never set it from `initState`/`dispose` — it would `setState` the banner mid-build).
- **Habits** — logs, locally-derived streaks, archive. Ở Dashboard, chạm một thói quen **không tick ngay** mà mở `showHabitLogSheet` ([habit_log_sheet.dart](lib/widgets/habit_log_sheet.dart)): lịch 28 ngày chỉ để xem (`HabitCalendarGrid`) + câu hỏi "Đã hoàn thành hôm nay chưa?" với nút "Hoàn thành" / "Bỏ lỡ" (`HabitTodayLogPanel`, dùng chung với trang chi tiết); sheet chỉ trả `true`/`false`/`null`, `DashboardScreen._logHabit` mới ghi log (cả "Bỏ lỡ" cũng làm thói quen biến khỏi danh sách "còn lại hôm nay").
- **Checklists** — categories → templates → template items, and runs → run items.

## UI conventions (iOS-style)

Giao diện theo phong cách iPhone. Khi thêm/sửa UI, dùng các khối chung thay vì viết lại:

- **Token & hình dạng** — [lib/theme/app_tokens.dart](lib/theme/app_tokens.dart): `AppRadius` (8/12/14/16/20/28/pill), `AppSpacing`, `AppMotion`, `AppShape.squircle(r)` (bo góc squircle `RoundedSuperellipseBorder`; đặt `AppShape.useSuperellipse = false` để quay về bo góc thường). Thẻ tự vẽ dùng `ShapeDecoration`, không dùng `BoxDecoration(borderRadius: ...)` với số rời.
- **Màu theo sáng/tối** — extension `context.appPrimary / appSurface / appTextSecondary / appDivider / appPrimarySoft / appDangerSoft...` trong [app_colors.dart](lib/theme/app_colors.dart); không viết lại `isDark ? AppColors.xDark : AppColors.x`. Chỉ phụ thuộc `Theme.brightness` nên chạy được với `MaterialApp` theme mặc định (test). Nền nút điền dùng `AppColors.accentFill` (chữ trắng luôn đủ tương phản).
- **Theme** — [app_theme.dart](lib/theme/app_theme.dart) đã theme dialog, bottom sheet (có tay nắm), snackbar floating, chip, switch, checkbox tròn, nút, input, tab, picker và chuyển trang kiểu Cupertino (vuốt-quay-lại). Đừng tự vẽ tay nắm/bo góc cho sheet; dùng `showAppSheet` (luôn `isScrollControlled`, không có tuỳ chọn tắt) + `AppSheetScaffold` (tiêu đề + thân **cùng cuộn được**) hoặc `AppSheetHeader` ([app_sheet.dart](lib/widgets/app_sheet.dart)), `showAppConfirmDialog` (`AlertDialog(scrollable: true)`), `showAppSnack` ([app_snack.dart](lib/utils/app_snack.dart)). Đừng đặt `Column(mainAxisSize: min)` trần trong sheet/dialog có nhiều nội dung — bọc trong `AppSheetScaffold`/`SingleChildScrollView`; `AlertDialog` có `TextField` thì đặt `scrollable: true`.
- **Thành phần** — `AppSurface` (thẻ), `AppListSection` + `AppListTile` + `AppClearButton` (nhóm hàng inset), `AppSegmentedControl`, `PrimaryButton` (variant primary/tonal/destructive/text), `Pressable` (hiệu ứng nhấn scale), `AppSpinner` / `AppErrorState` / `EmptyState`, `WeekdayPicker`, `UserAvatar`, `RunStatusChip`. Thẻ có nền đặc **không** dùng `InkWell` (ripple bị che) — dùng `AppSurface(onTap:)` hoặc `Pressable`.
- **Haptic** — `AppHaptics.selection/light/medium/heavy` (an toàn trong test). Dùng cho tick hoàn thành, đổi tab/segment/công tắc, kéo sắp xếp, xoá.
- **Không animation lặp vô hạn** ở Focus screen và note editor (test dùng `pumpAndSettle`); số trong `ScoreRing` không count-up (test đọc ngay giá trị). Mọi animation khác phải hữu hạn.
- **Chống "Bottom/Right overflowed"** — (1) lưới/ô có chiều cao cố định phải co giãn theo `MediaQuery.textScalerOf(context)` **và** bọc từng ô bằng `ClampTextScale(maxScale: ...)` ([clamp_text_scale.dart](lib/widgets/clamp_text_scale.dart)) để chữ trong ô không vượt chiều cao đã tính (xem `EisenhowerGrid`, `CalendarScreen`, `HabitsListScreen`, `HabitDetailScreen`) thay vì `childAspectRatio` cố định; (2) vùng có kích thước cố định nhưng nội dung không đoán trước được (xem trước todo, ô vuông `TodoFlagButton`, chip `Row`) dùng `FittedBox(scaleDown)` / `Flexible` + `TextOverflow.ellipsis` / `ClipRect(SingleChildScrollView(NeverScrollable))` làm lưới an toàn; (3) trạng thái rỗng/lỗi (`EmptyState`, `AppErrorState`) và nội dung form dài phải cuộn được; màn hình có cột cố định + `Expanded` thì đưa phần cố định vào trong danh sách cuộn (`header`/`footer` của `ReorderableListView`, phần tử đầu của `ListView`). Bộ kiểm thử [overflow_stress_test.dart](test/overflow_stress_test.dart) dựng widget/màn hình dùng chung ở 3 cỡ màn hình × chữ 1.0/1.5/2.0 × sáng/tối × có/không bàn phím với nội dung rất dài — thêm widget mới có kích thước cố định thì thêm một ca vào đó. Lưu ý trong `flutter test` font mặc định là Ahem (rộng hơn Roboto thật nhiều) nên test khắt khe hơn thực tế.

## Testing

Tests live in `test/` and cover models, utils, widgets, and the sync contract (`sync_payload_test.dart`, `sync_pull_contract_test.dart`, `sync_push_contract_test.dart`, `sync_resilience_test.dart`, `sync_user_scope_test.dart`). Sync/DB tests build an in-memory Drift instance per test (`AppDatabase.forTesting(NativeDatabase.memory())`), so there's no shared fixture state to worry about between test files.

## Lint baseline

`analysis_options.yaml` extends `package:flutter_lints/flutter.yaml` with no custom rules or overrides. Run `flutter analyze` before declaring work complete.

## Other gotchas

- `pubspec.lock` is managed by `flutter pub get` — don't hand-edit it.
- `android/app/build.gradle.kts` still uses `applicationId = "com.example.todonote"` and signs release builds with the debug config — needs fixing before a real release.
- UI copy is Vietnamese by existing convention; match that tone/language for new user-facing strings.
