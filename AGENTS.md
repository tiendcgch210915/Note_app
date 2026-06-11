# AGENTS.md

Hướng dẫn cho coding agents khi làm việc trong repository này.

## Tổng quan dự án

`todonote` là ứng dụng Flutter/Dart cho productivity, gồm các module chính:

- Authentication bằng JWT, lưu token/user qua `flutter_secure_storage`.
- Dashboard và calendar overview.
- Todos với Eisenhower matrix, frog task, subtasks, habit-stacking trigger, recurrence và offline/sync một phần.
- Notes với free/Cornell notes, tags, note links và todo links.
- Habits với logs, streaks, archive và offline/sync một phần.
- Checklists với categories, templates, template items, runs và run items.
- Local SQLite bằng Drift, có sync queue và push/pull worker.

Package Flutter: `todonote`.
Dart SDK constraint: `^3.8.1`.
Platform hiện có trong checkout: Android. Không có thư mục `ios/`.

## Cấu trúc dự án

```text
.
|-- lib/
|   |-- main.dart                     # Entry point: runApp(MyApp)
|   |-- app.dart                      # Bootstrap: auth, Drift DB, health check, sync, theme
|   |-- data/
|   |   |-- api_client.dart            # REST client dùng package http
|   |   |-- api_exception.dart         # ApiException + message mapping
|   |   |-- auth_repository.dart       # Login/register/logout/current user
|   |   |-- auth_storage.dart          # JWT + user JSON trong secure storage
|   |   |-- *_repository.dart          # Repositories theo domain
|   |   |-- remote/                    # Dio client/API cho sync/auth phụ trợ
|   |   `-- local/
|   |       |-- database.dart          # Drift database singleton, schemaVersion = 6
|   |       |-- tables.dart            # Drift table definitions
|   |       |-- model_converters.dart  # Domain model <-> Drift companion
|   |       `-- dao/                   # Drift DAOs
|   |-- models/                        # Domain models + JSON parsing
|   |-- screens/                       # UI screens grouped by feature
|   |-- sync/                          # Connectivity listener, sync worker, payloads, status notifier
|   |-- theme/                         # AppColors, AppTextStyles, AppTheme
|   |-- utils/                         # Date/json/quadrant/recurrence/uuid/helper logic
|   `-- widgets/                       # Reusable Flutter widgets
|-- test/                              # Widget, model, helper, sync payload tests
|-- android/                           # Android project, Gradle Kotlin DSL
|-- pubspec.yaml                       # Dependencies and Flutter config
|-- build.yaml                         # Drift build_runner options
|-- analysis_options.yaml              # flutter_lints baseline
|-- README.md                          # Default Flutter README, not authoritative
`-- CLAUDE.md                          # Stale; do not rely on it as source of truth
```

Generated files include:

- `lib/data/local/database.g.dart`
- `lib/data/local/dao/*_dao.g.dart`

Do not edit generated `.g.dart` files by hand. Change `database.dart`, `tables.dart`, or DAO source files, then regenerate.

## Cách chạy

Install dependencies:

```bash
flutter pub get
```

Generate Drift code after changing Drift database/tables/DAO files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Run app in development:

```bash
flutter run
```

Run on a specific device:

```bash
flutter devices
flutter run -d <device_id>
```

Build Android APK:

```bash
flutter build apk
```

Clean generated build artifacts:

```bash
flutter clean
```

There is no Makefile or custom script layer; normal Flutter/Dart CLI commands are the source of truth.

## Cách test và kiểm tra

Run all tests:

```bash
flutter test
```

Run a specific test file:

```bash
flutter test test/widget_test.dart
flutter test test/sync_payload_test.dart
```

Current test coverage includes:

- `widget_test.dart`: smoke test that `MyApp` builds.
- `todo_model_test.dart` and `todo_trigger_candidates_test.dart`: todo JSON/trigger helper behavior.
- `habit_target_test.dart`: habit target and streak helpers.
- `dashboard_model_test.dart` and `eisenhower_grid_test.dart`: dashboard DTOs and Eisenhower widget behavior.
- `checklist_category_model_test.dart`: checklist category/template parsing.
- `sync_payload_test.dart`: sync push payload wire contract.

Static analysis:

```bash
flutter analyze
```

Format Dart code:

```bash
dart format .
```

Recommended before handing off code changes:

```bash
dart format .
flutter analyze
flutter test
```

For doc-only changes, tests may be unnecessary, but still check git status before handoff.

## Kiến trúc và luồng dữ liệu

### Bootstrap

`lib/main.dart` chỉ gọi `runApp(const MyApp())`.

`lib/app.dart` bootstraps:

- `AuthStorage.instance.init()` để hydrate token/user cache.
- `AppDatabase.instance` để mở Drift SQLite.
- `ApiClient.instance.healthCheck()` best-effort.
- `AuthRepository.instance.isAuthenticated()` để chọn `HomeShell` hoặc `LoginScreen`.
- `ConnectivitySync.instance.init()` để lắng nghe reconnect.
- `SyncWorker.registerPostPullHook(TodosRepository.instance.ensureAllRecurrenceInstances)`.
- Listener `needsReLoginNotifier` để quay về login khi Dio sync client nhận 401.
- Initial `SyncWorker.instance.sync()` nếu user đã authenticated.

Theme được quản lý bằng `AppThemeController` + `AppThemeScope`, không dùng Provider/Riverpod/Bloc.

### Networking

Có 2 HTTP client:

- `lib/data/api_client.dart`: dùng `package:http`, được repositories chính dùng cho REST.
- `lib/data/remote/api_client_dio.dart`: dùng Dio, dành cho sync worker và auth path phụ trợ.

Backend URL hiện đang hard-code ở cả hai client:

- API base: `https://todo-note-h8s1.onrender.com/api/v1`
- Health: `https://todo-note-h8s1.onrender.com/health`

Nếu cần đổi backend cho emulator/device, cập nhật cả `ApiClient.baseUrl`/`healthUrl` và Dio `BaseOptions.baseUrl`.

### Local DB và sync

Drift database nằm ở `lib/data/local/`:

- `tables.dart` định nghĩa schema.
- `database.dart` đăng ký tables/DAOs và migration; `schemaVersion` hiện là `6`.
- `dao/` chứa thao tác local CRUD, soft delete và sync queue.
- `model_converters.dart` chuyển domain model sang Drift companions.

Migrations hiện có:

- v1 -> v2: recurrence columns cho todos.
- v2 -> v3: recurrence end-date + template id.
- v3 -> v4: `completed_at` cho checklist run items.
- v4 -> v5: `trigger_after_todo_id` cho habit-stacking todos.
- v5 -> v6: checklist categories và `category_id` cho checklist templates.

Sync files nằm ở `lib/sync/`:

- `sync_worker.dart`: push queue trước, pull từ server sau, xử lý conflict/server version, LWW skip khi local có pending op mới hơn/đồng thời.
- `sync_payload.dart`: chuyển Drift row sang payload JSON cho `/sync/push`.
- `connectivity_sync.dart`: trigger sync khi reconnect và debounce 2 giây sau local write.
- `sync_status_notifier.dart`: `ValueNotifier` global cho trạng thái sync.

Soft delete dùng `deleted_at`; không hard-delete entity syncable trừ khi API/domain đã yêu cầu rõ.

### Offline behavior

Không giả định toàn app đã offline-first đồng đều.

- `TodosRepository`: reads chủ yếu REST; một số helper/detail có local fallback. REST-success cache vào Drift, không enqueue lại. Offline/local-first writes ghi Drift + enqueue `sync_queue`.
- `HabitsRepository`: metadata reads REST-first/cache Drift; habit create/update/delete có offline path một phần. Habit log writes là local-first, enqueue sync, rồi sync nền.
- `ChecklistsRepository`: categories/templates và một số runs có local cache/fallback; system category/template là read-only với update/delete.
- `NotesRepository` và `DashboardRepository`: hiện chủ yếu gọi REST trực tiếp.
- `SyncWorker` pull có tombstone handling, LWW skip, self-heal junction rows và remap references khi server đổi id.
- Habit streak được derive local từ logs cho UI nhanh/offline, rồi cache bằng `adoptStreak`; không enqueue habit update chỉ để đổi streak.
- Habit log offline có cơ chế resurrect-local-first cho tombstone cùng `(habitId, logDate)`.

Sau local write offline hoặc local-first, gọi `ConnectivitySync.instance.scheduleWriteSync()` nếu cần queue được đẩy sớm.

### Recurrence todos

Todos hỗ trợ recurrence qua các field:

- `recurrence_type`
- `recurrence_interval`
- `recurrence_days_of_week`
- `recurrence_end_date`
- `recurrence_template_id`

`Todo.isRecurrenceTemplate` là row có `recurrenceType != null` và `recurrenceTemplateId == null`.
`Todo.isRecurrenceInstance` là row có `recurrenceTemplateId != null`.

`TodosRepository.ensureAllRecurrenceInstances()` được gọi sau pull để tạo instance local idempotently trong horizon mặc định 30 ngày. Instance mới được ghi vào Drift và enqueue sync create.

## Quy ước code

- Dùng Dart/Flutter idioms hiện có: `StatefulWidget` + `setState`, repository singletons, `ValueNotifier` khi cần global lightweight state.
- Không thêm state management package mới nếu không có lý do rõ và scope đủ lớn.
- Domain models parse JSON bằng `fromJson`, thường map backend snake_case sang Dart camelCase.
- Date-only fields dùng định dạng `YYYY-MM-DD`; datetime dùng ISO-8601 UTC khi sync.
- Dùng helpers trong `lib/utils/json_utils.dart` và `lib/utils/date_utils.dart` cho parse/format date/color thay vì tự parse ad hoc.
- Dùng `newId()` trong `lib/utils/uuid_utils.dart` cho ID local/offline.
- UI dùng `AppColors`, `AppTextStyles`, `AppTheme` và widgets sẵn có trước khi tạo style/component mới.
- Giữ text UI tiếng Việt theo phong cách hiện có.
- `analysis_options.yaml` chỉ include `package:flutter_lints/flutter.yaml`; đừng tắt lint rộng nếu không cần.
- Chỉ comment khi giúp giải thích logic phức tạp; repo hiện có comment tiếng Việt/English lẫn nhau.

## Lưu ý quan trọng

- `CLAUDE.md` đang không còn đúng: nó mô tả app như Flutter counter scaffold. Code thực tế đã là productivity app nhiều module. Khi mâu thuẫn, ưu tiên source code hiện tại.
- `README.md` vẫn là README mặc định của Flutter, không đủ thông tin vận hành.
- `pubspec.lock` có thể thay đổi khi chạy `flutter pub get`; không sửa thủ công.
- `android/app/build.gradle.kts` đang dùng `applicationId = "com.example.todonote"` và release signing bằng debug config. Đổi trước khi release thật.
- Android main manifest hiện đã khai báo `INTERNET`; nếu thêm platform/build flavor mới, kiểm tra lại quyền network tương ứng.
- Khi đổi Drift schema, tăng `schemaVersion`, thêm migration phù hợp trong `database.dart`, rồi chạy build_runner.
- Tránh chỉnh thủ công artifacts/caches như `.dart_tool/`, `build/`, `.flutter-plugins-dependencies`; chỉ thay đổi nếu Flutter tooling hoặc repo policy yêu cầu.
- Nếu thay đổi API contract, kiểm tra đồng thời model `fromJson`, repository request body, Drift converter, DAO cache path và `SyncPayload`.
- Sync payload phải dùng đúng backend snake_case contract; đặc biệt các field recurrence, `trigger_after_todo_id`, `category_id`, `completed_at`.
- Server-originated data trong pull được ghi trực tiếp vào Drift; chỉ local user writes mới enqueue sync operations.
