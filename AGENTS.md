# AGENTS.md

Hướng dẫn cho coding agents khi làm việc trong repository này.

## Tổng quan dự án

`todonote` là ứng dụng Flutter/Dart cho productivity, gồm các module chính:

- Authentication bằng JWT, lưu token/user qua `flutter_secure_storage`.
- Dashboard và calendar overview.
- Todos với Eisenhower matrix, frog task, subtasks, habit-stacking trigger, recurrence và offline/sync một phần.
- Notes local-first với free/Cornell, pin/search/filter/pagination, Quill rich
  text, tags, outgoing links/backlinks và todo links.
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
|   |       |-- database.dart          # Drift database singleton, schemaVersion = 12
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
- `note_model_delta_test.dart` và `note_delta_utils_test.dart`: parse/fallback,
  sanitize và round-trip Quill Delta.
- `notes_repository_local_first_test.dart`: CRUD, Cornell optional sections,
  relation snapshots và offline cache của Notes.
- `note_editor_widget_test.dart`: chọn loại note và Cornell responsive layout.
- `sync_payload_test.dart`: sync push payload wire contract.
- `sync_resilience_test.dart`: sync retry/locking/cursor và decode Notes Quill
  Delta khi pull.

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

Có 2 HTTP client dùng chung `lib/data/api_config.dart`:

- `lib/data/api_client.dart`: dùng `package:http`, được repositories chính dùng cho REST.
- `lib/data/remote/api_client_dio.dart`: dùng Dio, dành cho sync worker và auth path phụ trợ.

Backend mặc định:

- API base: `https://todosnotes.onrender.com/api/v1`
- Health: `https://todosnotes.onrender.com/health`

Để đổi backend cho emulator/device hoặc build flavor, truyền
`--dart-define=TODO_NOTE_API_BASE_URL=<absolute-api-v1-url>`. Không hard-code
riêng URL trong từng HTTP client.

### Local DB và sync

Drift database nằm ở `lib/data/local/`:

- `tables.dart` định nghĩa schema.
- `database.dart` đăng ký tables/DAOs và migration; `schemaVersion` hiện là `12`.
- `dao/` chứa thao tác local CRUD, soft delete và sync queue.
- `model_converters.dart` chuyển domain model sang Drift companions.

Migrations hiện có:

- v1 -> v2: recurrence columns cho todos.
- v2 -> v3: recurrence end-date + template id.
- v3 -> v4: `completed_at` cho checklist run items.
- v4 -> v5: `trigger_after_todo_id` cho habit-stacking todos.
- v5 -> v6: checklist categories và `category_id` cho checklist templates.
- v6 -> v7: per-user checklist template ordering.
- v7 -> v8: checklist run duration.
- v8 -> v9: `habit_id` cho todos.
- v9 -> v10: local wall-clock `time` cho top-level todos.
- v10 -> v11: `user_id`, `last_error`, `is_dead_letter` cho sync queue; xóa
  legacy outbox/cursor không xác định được owner nhưng giữ nguyên entity cache.
- v11 -> v12: thêm `content_format`, `body_delta`, `cornell_cue_delta` và
  `cornell_summary_delta` cho Notes; các Delta columns là nullable.

Sync files nằm ở `lib/sync/`:

- `sync_worker.dart`: push queue của authenticated user trước, pull delta sau;
  xử lý conflict/server version, tombstone delete-wins, LWW bằng `DateTime`,
  Todo parent-before-child và atomic pull apply.
- `sync_payload.dart`: chuyển Drift row sang payload JSON cho `/sync/push`.
- `connectivity_sync.dart`: trigger sync khi reconnect và debounce 2 giây sau local write.
- `sync_status_notifier.dart`: `ValueNotifier` global cho trạng thái sync.

Soft delete dùng `deleted_at`; không hard-delete entity syncable trừ khi API/domain đã yêu cầu rõ.

`sync_queue` và cursor được scope theo authenticated user:

- Mọi queue row mới bắt buộc có `user_id`.
- Worker chỉ đọc/push/remove/retry queue của current user.
- Cursor dùng key `last_synced_at:<userId>`.
- Permanent error được giữ dạng dead-letter với `last_error`; không retry vô hạn.
- Pull phải có đủ 12 arrays và chỉ cập nhật cursor sau khi toàn bộ transaction
  apply thành công.

### Offline behavior

Không giả định toàn app đã offline-first đồng đều.

- `TodosRepository`: reads chủ yếu REST; một số helper/detail có local fallback. REST-success cache vào Drift, không enqueue lại. Offline/local-first writes ghi Drift + enqueue `sync_queue`.
- `HabitsRepository`: metadata reads REST-first/cache Drift; habit create/update/delete có offline path một phần. Habit log writes là local-first, enqueue sync, rồi sync nền.
- `ChecklistsRepository`: categories/templates/runs có hàm đọc Drift thuần
  (`listCategoriesLocal`, `listTemplatesLocal`, `listRunsLocal`,
  `getTemplateLocal`) để màn hình hiện ngay, rồi `listX`/`getTemplate`/
  `refreshRun` hỏi server và ghi cache; lỗi tạm thời (`isRetryable`) trả về
  cache. System category/template là read-only với update/delete.
- `NotesRepository`: reads dùng Drift trước và REST refresh sau; mọi CRUD,
  tag/link/todo relation write ghi Drift, enqueue full `note` payload với
  relation snapshot thật rồi schedule sync.
- `DashboardRepository`: hiện chủ yếu gọi REST trực tiếp.
- `SyncWorker` pull có tombstone handling, LWW skip, self-heal junction rows và remap references khi server đổi id.
- Habit streak được derive local từ logs cho UI nhanh/offline, rồi cache bằng `adoptStreak`; không enqueue habit update chỉ để đổi streak.
- Habit log offline có cơ chế resurrect-local-first cho tombstone cùng `(habitId, logDate)`.

### Đọc cache trước, hỏi server sau (Todos, Notes, Checklists)

Các màn danh sách/chi tiết của 3 module này phải vẽ từ Drift ngay khi mở, rồi
mới gọi REST và vẽ lại khi có kết quả (`TodosListScreen`, `NotesListScreen`,
`ChecklistsScreen`, `RunsHistoryScreen`, `TemplateDetailScreen`, `RunDetailScreen`).
Quy ước khi thêm/sửa màn hình kiểu này:

- Không `await` mạng trước khi có gì đó để hiện. Spinner toàn màn hình chỉ dành
  cho lúc cache rỗng; có cache thì dùng `LinearProgressIndicator` mỏng.
- Lỗi `ApiException.isRetryable` (mất mạng, timeout, 5xx) khi đã có dữ liệu để
  xem thì không báo snackbar. Lỗi khác (ví dụ 4xx) và cache rỗng vẫn phải báo.
- Hàm cache kết quả REST (`_cacheTodos`, `_cache*` của Checklists) bỏ qua
  entity đang có op chưa đồng bộ trong `sync_queue`, để bản cũ trên server không
  ghi đè thay đổi offline của người dùng. Hàm cache mới phải giữ quy ước này.
- REST delete xong phải xóa mềm bản trong Drift (như `deleteRun`/`deleteTemplate`),
  nếu không màn hình đọc cache sẽ hiện lại mục đã xóa.
- Sau khi sync pull áp dữ liệu, `SyncWorker` gọi `TodoLocalEvents`,
  `NoteLocalEvents`, `ChecklistLocalEvents`; màn đang mở lắng nghe để đọc lại
  Drift.
- Chưa áp dụng cho Dashboard/Lịch/Habits (vẫn REST-first).

Sau local write offline hoặc local-first, gọi `ConnectivitySync.instance.scheduleWriteSync()` nếu cần queue được đẩy sớm.

### Notes

Notes hỗ trợ hai loại:

- `free`: nội dung chính ở `body`.
- `cornell`: gồm `cornell_cue`, `body` và `cornell_summary`.

`Note` còn có `is_pinned`, tags, timestamps và metadata nội dung:

- `content_format`: `plain` hoặc `quill_delta_v1`; giá trị lạ fallback về
  `plain`.
- `body_delta`, `cornell_cue_delta`, `cornell_summary_delta`: JSON object hoặc
  null. Decoder chấp nhận object, JSON string và null; payload malformed được
  bỏ qua an toàn thay vì làm hỏng toàn bộ sync.
- Các field plain text là mirror/fallback cho note legacy và preview. Editor ưu
  tiên Delta hợp lệ, fallback từ plain text và lưu Delta document chỉ gồm
  operation `insert`.

Luồng UI hiện tại:

- `NotesListScreen` đọc cache ngay, search debounce 300 ms, filter all/free/
  Cornell, pinned-first, REST cursor pagination 20 item và pull-to-refresh.
- `NoteEditorScreen` dùng `flutter_quill`, autosave local sau 1 giây, serialize
  save, flush trước navigation/type/relation picker và hiển thị trạng thái lưu.
- Cornell dùng shared responsive layout: màn rộng Cues/Notes gần 30/70 và
  Summary full-width; màn hẹp xếp Notes, Cues, Summary.
- Cues/Summary là optional. Free -> Cornell không bị chặn; Cornell -> Free phải
  xác nhận vì local/backend sẽ clear dữ liệu Cornell.
- `NoteDetailScreen` là Quill read-only dùng cùng Cornell layout và hiển thị đủ
  tags, outgoing links, backlinks và linked Todos.

Local/sync storage gồm `notes`, `note_tags`, `note_links` và
`note_todo_links`. `SyncPayload.fromNote` gửi cả plain fields, Delta fields,
tag IDs, outgoing links và linked Todo IDs. Pull dùng LWW/pending-op guard,
reconcile các junction relations, xử lý tombstone và dọn relation mồ côi trong
transaction. Autosave content luôn đọc relation thật từ Drift trước khi
enqueue nên không gửi các relation arrays rỗng ngoài ý muốn. Create rồi delete
trước lần push đầu sẽ loại operation khỏi outbox.

### Focus session (đồng hồ tập trung)

- State của phiên nằm ở singleton `FocusSessionController`
  (`lib/utils/focus_session_controller.dart`), không nằm trong
  `TodoFocusScreen`. Đồng hồ tính theo wall-clock (`endsAt`) nên không lệch khi
  app ở nền. Chỉ lưu in-memory: không ghi Drift, không sync; tắt hẳn app thì
  phiên mất. Phiên bị hủy khi logout hoặc nhận 401.
- `TodoFocusScreen` có nút Home (về tab "Hôm nay"), nút Lịch (tab Lịch + vào
  thẳng `CalendarDayDetailScreen` của hôm nay, vốn đọc Drift trước) và nút X.
  Home/Lịch/back hệ thống chỉ rời màn hình, phiên vẫn chạy. Nút X luôn hiện
  hộp thoại xác nhận: "Trở lại" (như nút Home, đồng hồ chạy tiếp) hoặc "Hủy bấm
  giờ" (dừng phiên, về trang chi tiết của todo). Chạm ra ngoài hộp thoại là ở
  lại màn Focus. Nếu hủy sau khi quay lại từ banner và trang chi tiết của todo
  không nằm ngay bên dưới (`TodoDetailRouteTracker`), `resumeFocusSession()` sẽ
  mở lại trang chi tiết.
- Khi phiên chạy ngầm, `FocusSessionBannerHost` (trong `MaterialApp.builder`)
  hiện thanh dưới cùng chiếm chỗ thật trong layout (không phải overlay nổi để
  khỏi che bottom nav/FAB). Thanh ẩn khi màn Focus hoặc bàn phím đang mở; chạm
  để quay lại, nút dừng để kết thúc.
- Controller đọc lại todo từ Drift mỗi khi `TodoLocalEvents` đổi (gồm cả sync
  pull): todo bị xóa/hoàn thành ở nơi khác thì phiên ngầm tự kết thúc; tránh
  `completeLocalFirst` trên snapshot cũ (sẽ sinh occurrence recurrence thừa).
- Mở màn hình bằng `openTodoFocusScreen()` / `resumeFocusSession()` (đặt cờ
  `focusScreenOpen`), không `Navigator.push` trực tiếp. Bắt đầu việc khác khi
  đang có phiên phải xin xác nhận trước khi gọi `start()` (thay thế phiên cũ).
- Test: `test/focus_session_controller_test.dart`,
  `test/focus_session_ui_test.dart`.

### Recurrence todos

Todos hỗ trợ recurrence qua các field:

- `recurrence_type`
- `recurrence_interval`
- `recurrence_days_of_week`
- `recurrence_end_date`
- `recurrence_template_id`

`Todo.isRecurrenceTemplate` là row có `recurrenceType != null` và `recurrenceTemplateId == null`.
`Todo.isRecurrenceInstance` là row có `recurrenceTemplateId != null`.

Recurrence dùng mô hình one-actionable-occurrence:

- Khi complete recurring top-level Todo local-first, Mobile materialize đúng một
  occurrence kế tiếp hợp lệ.
- Occurrence kế tiếp clone toàn bộ active subtask tree theo thứ tự
  parent-before-child, remap `parent_id` và trigger nội bộ, giữ tag/metadata,
  reset runtime state, rồi enqueue create theo cùng thứ tự.
- Subtask không tự có recurrence, `scheduled_date` hoặc `time`.
- Nếu server trả occurrence canonical cùng series/date nhưng khác ID, Mobile
  purge toàn bộ local generated subtree và pending operations trước khi adopt
  cây server qua pull.
- Tombstone của occurrence là recurrence exception; repair không được tạo lại
  ngày đã xóa. Scoped delete dùng `this`, `future`, hoặc `all`.

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
- Sync payload phải dùng đúng backend snake_case contract; đặc biệt các field
  recurrence, `trigger_after_todo_id`, `category_id`, `completed_at` và Notes
  Delta (`content_format`, `body_delta`, `cornell_cue_delta`,
  `cornell_summary_delta`).
- Server-originated data trong pull được ghi trực tiếp vào Drift; chỉ local user writes mới enqueue sync operations.
