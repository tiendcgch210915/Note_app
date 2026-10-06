# Mobile Sync & Local-First Audit

Ngày audit: 2026-06-24  
Repository: Flutter package `todonote`  
Mục đích: tài liệu bàn giao cho Codex/back-end để đối chiếu và chuẩn hóa sync contract.

## 0. Trạng thái triển khai sau audit

Cập nhật ngày 2026-06-24. Phần còn lại của tài liệu giữ nguyên kết quả audit
trước khi sửa để không che giấu lịch sử. Khi có mâu thuẫn, trạng thái dưới đây
và source hiện tại là nguồn sự thật:

| Finding | Trạng thái sau sửa |
|---|---|
| Cursor/outbox dùng chung tài khoản | Đã sửa. Schema v11 thêm `sync_queue.user_id`; mọi thao tác queue và cursor `last_synced_at:<userId>` được scope theo authenticated user. Migration xóa legacy queue/global cursor không xác định owner, không xóa entity cache. |
| Todo gửi `linked_note_ids: []` | Đã sửa. Todo sync payload không còn gửi `linked_note_ids`; Note-Todo relations tiếp tục do Note payload/REST quản lý. |
| Tombstone gặp pending write | Đã sửa theo delete-wins. Pull tombstone clear pending operations, apply tombstone và dọn junction/subtree trước cycle kế tiếp. |
| Pull không atomic | Đã sửa. Network fetch/validation ở ngoài transaction; toàn bộ 12 arrays, junction cleanup và cursor update apply trong một Drift transaction. Lỗi bất kỳ rollback toàn bộ và không đổi cursor. |
| Todo child có thể apply trước parent | Đã sửa. `changes.todos` được topological sort theo depth, position và ID trước khi apply. |
| Retry permanent vô hạn | Đã sửa. Retryable error có backoff và giới hạn; permanent error/depleted retry trở thành dead-letter có `last_error`. Delete `not_found` là idempotent success; update `not_found` là terminal. |
| LWW so sánh timestamp dạng String | Đã sửa. Timestamp được parse bằng `DateTime.parse`; timestamp invalid làm sync fail với diagnostic và transaction rollback. |
| Thiếu pull key bị coi là empty | Đã sửa. Mobile bắt buộc đủ 12 key và mỗi value phải là `List`. |
| SyncWorker integration tests | Đã bổ sung test fake Dio + in-memory Drift cho atomic pull, cursor, tombstone, topological Todo, account isolation, retry/permanent errors và batch lớn. |
| Recurring Todo chỉ clone parent | Đã sửa. Complete local-first clone một occurrence kế tiếp cùng toàn bộ active subtree, tags, parent/trigger remap và queue parent-before-child. |
| Reconcile occurrence khác ID để orphan child | Đã sửa. Local duplicate occurrence được purge cùng descendants, junctions và pending operations trước khi server tree được apply. |
| ID remap tổng quát cho server-generated ID | Chủ động để lại. Contract hiện yêu cầu backend preserve UUID v7 do Mobile tạo; conflict remap tổng quát cho mọi graph entity vẫn chưa hoàn chỉnh. |
| Notes local-first | Đã sửa ngày 2026-06-26. Notes CRUD và relations ghi Drift trước, enqueue full relation snapshot, dùng Quill Delta insert-only, đọc cache trước rồi REST refresh. |
| User pull cập nhật `AuthStorage` | Chủ động để lại. Canonical user được ghi Drift nhưng secure cached profile chưa được reconcile trong thay đổi này. |
| Applied result chứa server normalization | Chủ động để lại. Worker vẫn dựa vào pull ngay sau push để nhận canonical server row. |

Verification sau triển khai:

- `dart run build_runner build --delete-conflicting-outputs`: pass.
- `dart format .`: pass.
- `flutter analyze`: pass, không có issue.
- `flutter test --concurrency=1`: pass, 83 tests.
- `flutter build apk --debug`: pass.

## 1. Kết luận điều hành

Mobile hiện không phải một ứng dụng offline-first đồng nhất. Kiến trúc thực tế là
hybrid:

- `Todos`: các luồng UI chính như tạo, sửa, hoàn thành, mở lại, xóa, đổi tag
  đang local-first.
- `Habit logs`: local-first.
- `Habits`: tạo là REST-first có fallback offline; sửa trong UI là local-first;
  archive/unarchive và một số read vẫn cần REST.
- `Checklists`: category/template item/template order/run/run item phần lớn
  local-first, nhưng sửa/xóa template và xóa run vẫn online-only.
- `Tags`: REST-first có fallback; riêng selector của Todo có thể tạo tag
  local-first trực tiếp.
- `Notes`: local-first cho CRUD, tags, note links và Todo links; UI đọc Drift
  trước, REST chỉ refresh cache khi không có pending note write.
- `Dashboard`: tải local trước để phản hồi nhanh, sau đó gọi REST và thay dữ
  liệu bằng server response; khi còn pending writes, local snapshot được ưu
  tiên lại.

Sync dùng mô hình outbox:

1. Local write ghi Drift.
2. Mobile enqueue một operation vào `sync_queue`.
3. Sau debounce 2 giây, reconnect, app resume, app boot, hoặc nhấn nút sync,
   `SyncWorker` chạy.
4. Worker push tối đa 100 operations mỗi batch.
5. Khi push xong, worker pull delta.
6. `last_synced_at` chỉ được lưu bằng `response.server_time` sau khi toàn bộ
   danh sách pull đã apply thành công.

Hai endpoint sync hiện được Mobile gọi là:

```text
GET  https://todo-note-h8s1.onrender.com/api/v1/sync/changes
POST https://todo-note-h8s1.onrender.com/api/v1/sync/push
```

Cả hai được Dio interceptor gắn:

```http
Authorization: Bearer <JWT>
```

Pull hiện kỳ vọng **12 nhóm dữ liệu**, không còn là 10 nhóm:

```text
users
tags
todos
notes
habits
habit_logs
checklist_categories
checklist_templates
checklist_template_orders
checklist_template_items
checklist_runs
checklist_run_items
```

Điểm cần back-end lưu ý nhất:

1. Back-end nên giữ nguyên UUID do Mobile tạo. ID remap trên Mobile hiện chỉ
   hoàn chỉnh một phần cho `tag` và `habit_log`.
2. `server_time`, `updated_at`, `created_at`, `deleted_at` phải là ISO-8601 UTC
   chuẩn hóa, tốt nhất dạng `2026-06-05T08:00:00.000Z`.
3. Push result phải dùng `id` là ID trong operation ban đầu để Mobile ghép kết
   quả với outbox.
4. Pull phải trả tombstone và relation data nhất quán.
5. Back-end không được tin `user_id` trong payload; user scope phải lấy từ JWT.
6. Todo sync payload không gửi `linked_note_ids`; quan hệ Todo-Note tiếp tục
   được quản lý từ Note payload hoặc REST Note APIs.
7. Cursor/outbox đã được scope theo authenticated user từ schema v11. Backend
   vẫn phải enforce ownership bằng JWT.

## 2. Source được audit

Các file lõi:

- `lib/sync/sync_worker.dart`
- `lib/sync/sync_payload.dart`
- `lib/sync/connectivity_sync.dart`
- `lib/sync/sync_status_notifier.dart`
- `lib/data/remote/api_client_dio.dart`
- `lib/data/api_client.dart`
- `lib/data/auth_storage.dart`
- `lib/data/local/tables.dart`
- `lib/data/local/database.dart`
- `lib/data/local/dao/sync_dao.dart`
- `lib/data/local/dao/*_dao.dart`
- `lib/data/*_repository.dart`
- `lib/data/local/model_converters.dart`
- các model JSON trong `lib/models/`
- các call site trong `lib/screens/`
- test sync/recurrence/local DB trong `test/`

Không tìm thấy tài liệu `API_CONTRACT.md` trong checkout hiện tại, dù comment
trong source có nhắc tới nó. Báo cáo này lấy source hiện tại làm nguồn sự thật.

## 3. Networking và authentication

### 3.1 Hai HTTP client

Mobile có hai client:

| Client | Package | Vai trò |
|---|---|---|
| `ApiClient` | `package:http` | REST endpoints của repositories |
| `ApiClientDio` | Dio | Chỉ dùng cho SyncWorker |

Cả hai đang hard-code base URL:

```text
https://todo-note-h8s1.onrender.com/api/v1
```

Health endpoint:

```text
https://todo-note-h8s1.onrender.com/health
```

### 3.2 Token

Login/register nhận:

```json
{
  "token": "<JWT>",
  "user": {
    "id": "...",
    "email": "...",
    "display_name": "...",
    "avatar_url": null,
    "timezone": "Asia/Ho_Chi_Minh"
  }
}
```

Token và user JSON được lưu bằng `flutter_secure_storage`.

Sync Dio interceptor tự thêm Bearer token. Khi sync nhận HTTP 401:

1. Mobile xóa token/user khỏi secure storage.
2. Phát `needsReLoginNotifier`.
3. App quay về login.

REST client cũng thêm Bearer token nhưng không có cơ chế 401 toàn cục tương tự.

### 3.3 Yêu cầu bảo mật đối với back-end

- Mọi sync query/write phải được scope hoàn toàn bằng user từ JWT.
- Không dùng `payload.user_id` để xác định owner.
- Nếu `payload.user_id` khác JWT user, nên bỏ qua field hoặc trả
  `forbidden`/`bad_input`.
- System records có `user_id = null` chỉ được sửa bởi server/admin logic.
- Không trả password hash, token, secret hoặc field nhạy cảm trong pull hay
  `server_version`.

## 4. Drift local database

Database: SQLite qua Drift, tên `todonote_db`.

`schemaVersion` hiện tại là **11**.

Các bảng syncable:

| Local table | Entity type khi push | Pull key |
|---|---|---|
| `users` | `user` | `users` |
| `tags` | `tag` | `tags` |
| `todos` | `todo` | `todos` |
| `notes` | `note` | `notes` |
| `habits` | `habit` | `habits` |
| `habit_logs` | `habit_log` | `habit_logs` |
| `checklist_categories` | `checklist_category` | `checklist_categories` |
| `checklist_templates` | `checklist_template` | `checklist_templates` |
| `checklist_template_orders` | `checklist_template_order` | `checklist_template_orders` |
| `checklist_template_items` | `checklist_template_item` | `checklist_template_items` |
| `checklist_runs` | `checklist_run` | `checklist_runs` |
| `checklist_run_items` | `checklist_run_item` | `checklist_run_items` |

Junction/relation tables:

- `todo_tags`
- `note_tags`
- `note_links`
- `note_todo_links`

Các bảng hỗ trợ:

- `sync_queue`: outbox theo `user_id`, có `last_error` và dead-letter state.
- `sync_meta`: key-value, cursor dùng `last_synced_at:<userId>`.
- `reminders`: local-only, back-end chưa hỗ trợ, không sync.

Không có foreign key constraint trong Drift schema hiện tại. Quan hệ được giữ
bằng convention và self-heal logic.

Tất cả entity chính dùng soft delete qua `deleted_at`. DAO read bình thường
lọc `deleted_at IS NULL`.

## 5. Sync lifecycle và trigger

Sync được trigger ở các thời điểm:

- App bootstrap khi đã có token.
- `HomeShell` sau frame đầu.
- App quay lại foreground.
- Thiết bị chuyển từ offline sang có network interface.
- Sau local write với debounce 2 giây.
- Người dùng nhấn icon sync khi có pending/error.

Worker có cờ `_syncing`; nếu đang chạy, trigger mới bị bỏ qua.

Một full cycle luôn:

```text
pushPending()
pullChanges()
```

Nếu không có token, worker bỏ qua.

`connectivity_plus` chỉ báo có network interface, không đảm bảo Internet hoặc
backend thực sự truy cập được.

## 6. Outbox và coalescing

Mỗi row `sync_queue` có:

```text
id              auto-increment, dùng để FIFO
user_id         authenticated owner
entity_type     singular enum
entity_id
operation       create | update | delete
payload         JSON string
retry_count
next_retry_at   epoch millis, null = gửi ngay
last_error      nullable diagnostic
is_dead_letter  terminal state, không tự retry
created_at      ISO UTC
```

Mỗi `(user_id, entity_type, entity_id)` về thực tế chỉ giữ một operation.
Khi enqueue operation mới:

| Existing | New | Kết quả |
|---|---|---|
| none | bất kỳ | insert |
| create | update | giữ `create`, thay payload mới |
| create/update | delete | đổi thành `delete` |
| update | update | `update`, payload mới |
| delete | create/update | operation mới ghi đè delete |

Lưu ý: trường hợp entity được tạo offline rồi xóa trước khi từng push sẽ trở
thành một `delete` cho ID server chưa biết. Back-end nên xử lý delete unknown ID
idempotently hoặc Mobile phải sửa coalescing để loại bỏ operation hoàn toàn.

## 7. Push contract

### 7.1 Request

Worker chỉ POST khi có ít nhất một operation đến hạn.

Batch tối đa 100:

```http
POST /api/v1/sync/push
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "operations": [
    {
      "op": "create",
      "type": "todo",
      "payload": {
        "id": "019...",
        "title": "Example",
        "updated_at": "2026-06-24T08:00:00.000Z"
      }
    }
  ]
}
```

`type` luôn là singular enum. Không dùng `todos`, `habits`, v.v.

### 7.2 Push dependency order

Mobile lấy toàn bộ due operations của current user để dependency-sort ổn định,
sau đó gửi tối đa 100 operations đầu tiên theo thứ tự:

```text
tag
habit
checklist_category
checklist_template
checklist_template_order
note
todo
checklist_template_item
habit_log
checklist_run
checklist_run_item
user
```

Trong cùng entity type, giữ FIFO theo queue ID.

Back-end vẫn phải xử lý mỗi operation độc lập và trả result cho từng operation.
Không nên giả định quan hệ cha luôn tồn tại nếu batch bị cắt tại ranh giới 100.

### 7.3 Response Mobile đang hiểu

```json
{
  "server_time": "2026-06-24T08:00:01.000Z",
  "results": [
    {
      "id": "client-operation-entity-id",
      "status": "applied"
    },
    {
      "id": "another-id",
      "status": "conflict",
      "server_version": {
        "id": "another-id",
        "updated_at": "2026-06-24T08:00:00.500Z"
      }
    },
    {
      "id": "third-id",
      "status": "error",
      "error": "bad_input"
    }
  ]
}
```

`server_time` trong push response hiện không được dùng để cập nhật cursor.

`results[].id` bắt buộc phải là ID trong operation gửi lên. Mobile ghép result
với outbox bằng ID này, không bằng index và không bằng server-generated ID.

### 7.4 Result handling

`applied`:

- Xóa operation khỏi outbox.
- Mobile bỏ qua `server_version` nếu back-end có trả kèm.
- Vì vậy, applied create phải giữ nguyên client ID hoặc Mobile sẽ không adopt
  được server ID.

`conflict`:

- Bắt buộc có `server_version`.
- Mobile áp server version vào Drift.
- Server thắng; operation bị xóa.
- Nếu `server_version.id` khác local ID, Mobile sửa reference trong pending
  payloads.
- ID remap trong local DB chỉ được xử lý tương đối đầy đủ cho `tag` và
  `habit_log`; các entity khác chưa an toàn.

`error: read_only`:

- Với update/delete `checklist_template` hoặc `checklist_category`, Mobile xóa
  operation để không retry mãi.

`error: invalid_habit`:

- Với Todo, Mobile tự xóa `habit_id`, cập nhật `updated_at`, reset retry và thử
  lại.

Retryable errors tăng retry với exponential backoff, tối đa 300 giây giữa hai
lần và có giới hạn retry. Permanent errors như `bad_input`, `forbidden`,
`read_only`, invalid ownership hoặc payload validation được giữ ở dead-letter
với `last_error`. Delete `not_found` được coi là idempotent success; update
`not_found` là terminal để không retry vô hạn.

Nếu response thiếu result cho một operation, Mobile coi là lỗi retryable.

### 7.5 Logging

Log sync failure đã được sanitize ở mức không log request header/token/password.
Log gồm:

- method
- path
- HTTP status
- response error body
- operation count
- count theo `entity_type:operation`
- result summary

Response body log bị cắt ở 1500 ký tự. Với push result, `server_version` không
được dump; log chỉ ghi `has_server_version`.

## 8. Push payload theo entity

Quy ước chung:

- Boolean là JSON `true`/`false`.
- Date-only là `YYYY-MM-DD`.
- Datetime là ISO-8601 UTC.
- Null được giữ rõ trong full payload.
- Local ID được tạo bằng UUID v7.

### 8.1 `tag`

```text
id
name
color
user_id
created_at
updated_at
deleted_at
```

Không push: `usage_count`, `last_used_at`.

Mobile có resurrect-local-first: nếu tạo lại tag cùng tên đã tombstone, reuse ID
cũ.

### 8.2 `todo`

Top-level Todo:

```text
id
user_id
parent_id
title
description
status
position
is_frog
frog_date
is_important
is_urgent
estimated_minutes
actual_minutes
start_at
due_at
scheduled_date
time
trigger_after_todo_id
habit_id
completed_at
recurrence_type
recurrence_interval
recurrence_days_of_week
recurrence_end_date
recurrence_template_id
tag_ids
created_at
updated_at
deleted_at
```

Subtask giữ metadata và tags mà local schema hỗ trợ, nhưng vẫn bị ép các
invariant domain:

```text
scheduled_date = null
time = null
recurrence_* = null
```

Todo payload không gửi `linked_note_ids`. `tag_ids` là full replacement và
subtask gửi tag IDs thật.

Delete recurring Todo dùng payload rút gọn:

```json
{
  "id": "...",
  "delete_scope": "this",
  "deleted_at": "2026-06-24T08:00:00.000Z",
  "updated_at": "2026-06-24T08:00:00.000Z"
}
```

`delete_scope`:

- `this`
- `future`
- `all`

Mobile chủ động không gửi `linked_note_ids` trong Todo create/update vì field
này không đại diện cho intent quản lý relation ở Todo outbox.

### 8.3 `note`

Payload mapper có hỗ trợ:

```text
id
user_id
title
type
body
cornell_cue
cornell_summary
is_pinned
tag_ids
note_links
linked_todo_ids
created_at
updated_at
deleted_at
```

Tuy nhiên repository hiện không enqueue Note operation. Đây mới là khả năng
mapper/worker, chưa phải luồng UI local-first đang hoạt động.

### 8.4 `habit`

```text
id
user_id
title
description
icon
color
frequency_type
target_per_period
active_weekdays
start_date
end_date
is_archived
created_at
updated_at
deleted_at
```

Không push:

- `current_streak`
- `longest_streak`

Streak được coi là server-authoritative trong sync payload, dù Mobile có derive
tạm từ logs để UI phản hồi nhanh.

### 8.5 `habit_log`

```text
id
habit_id
user_id
log_date
completed
note
created_at
updated_at
deleted_at
```

Mobile cố duy trì một active log cho mỗi `(habit_id, log_date)`:

- Reuse tombstoned ID khi tạo lại.
- Soft-delete duplicate local logs.
- Sau pull/conflict cũng soft-delete duplicate.

Back-end nên có unique semantic tương ứng và trả canonical row trong conflict.

### 8.6 `checklist_category`

```text
id
user_id
name
slug
icon
color
sort_order
created_at
updated_at
deleted_at
```

Không push `is_system`.

### 8.7 `checklist_template`

```text
id
user_id
title
description
icon
category
category_id
sort_order
created_at
updated_at
deleted_at
```

Không push:

- `is_system`
- `times_used`
- `last_used_at`

### 8.8 `checklist_template_order`

```text
id
user_id
template_id
sort_order
created_at
updated_at
deleted_at
```

Đây là per-user order row, tách khỏi fallback `template.sort_order`.

### 8.9 `checklist_template_item`

```text
id
template_id
title
description
is_required
position
created_at
updated_at
deleted_at
```

Local column `order_index` được map thành wire key `position`.

### 8.10 `checklist_run`

```text
id
template_id
user_id
name
status
completed_at
duration_ms
started_at
created_at
updated_at
deleted_at
```

Local lưu `started_at` trong column `created_at`, nên payload gửi cả hai field.

### 8.11 `checklist_run_item`

```text
id
run_id
template_item_id
status
completed_at
note
created_at
updated_at
deleted_at
```

Không push denormalized snapshot:

- `title`
- `description`
- `is_required`
- `position`/`order_index`

Back-end phải derive/snapshot các field hiển thị từ template item khi cần.

### 8.12 `user`

Mapper chỉ cho phép:

```text
id
display_name
avatar_url
timezone
settings
created_at
updated_at
deleted_at
```

Không push:

- `email`
- password/password hash

Hiện chưa có repository enqueue user operation.

## 9. Pull contract

### 9.1 Request

Initial pull:

```http
GET /api/v1/sync/changes
Authorization: Bearer <token>
```

Delta pull:

```http
GET /api/v1/sync/changes?since=2026-06-24T08%3A00%3A00.000Z
Authorization: Bearer <token>
```

`since` được lấy nguyên văn từ
`sync_meta['last_synced_at:<authenticatedUserId>']`, vốn được lưu từ
`response.server_time`.

### 9.2 Response

Shape Mobile yêu cầu:

```json
{
  "server_time": "2026-06-24T08:00:01.000Z",
  "changes": {
    "users": [],
    "tags": [],
    "todos": [],
    "notes": [],
    "habits": [],
    "habit_logs": [],
    "checklist_categories": [],
    "checklist_templates": [],
    "checklist_template_orders": [],
    "checklist_template_items": [],
    "checklist_runs": [],
    "checklist_run_items": []
  }
}
```

Mobile bắt buộc `server_time`, `changes`, đủ cả 12 key và mỗi value phải là
`List`. Thiếu key hoặc sai type làm sync fail, rollback apply và không cập nhật
cursor.

### 9.3 Delta boundary

Để không mất record phát sinh đúng tại boundary:

- Khuyến nghị query theo `updated_at > since` nếu `server_time` được lấy trước
  query và transaction/isolation đảm bảo.
- Hoặc dùng `(updated_at, id)` cursor ổn định.
- Nếu dùng `updated_at >= since`, response phải idempotent; Mobile upsert được.
- `server_time` phải đại diện cho snapshot boundary của chính response, không
  phải thời điểm tùy ý sau khi query.

Back-end cần đảm bảo clock server là nguồn chuẩn; không dựa vào clock Mobile để
lọc delta.

### 9.4 Tombstone

Record có `deleted_at != null` được coi là tombstone.

Tombstone tối thiểu cho hầu hết entity:

```json
{
  "id": "...",
  "updated_at": "2026-06-24T08:00:00.000Z",
  "deleted_at": "2026-06-24T08:00:00.000Z"
}
```

Riêng tag tombstone hiện đi qua full tag converter, nên cần thêm:

```text
name
created_at
updated_at
```

Để đơn giản và ổn định, back-end nên trả full row cho mọi tombstone.

### 9.5 Apply order hiện tại

Mobile apply theo thứ tự:

```text
users
tags
todos
notes + note relations
habits
habit_logs
checklist_categories
checklist_templates
checklist_template_orders
checklist_template_items
checklist_runs
checklist_run_items
self-heal tombstoned relations
save last_synced_at:<userId>
commit transaction
fire post-pull recurrence repair/events
```

`changes.todos` được topological sort trước khi apply: top-level trước,
parent-before-child, depth tăng dần, position và ID làm tie-breaker. Toàn bộ
apply và cursor update nằm trong một Drift transaction; post-pull repair chỉ
chạy sau commit.

### 9.6 Relation reconciliation

Todo upsert:

- `tag_ids` là full replacement.
- Subtask cache `tag_ids` thật từ server.
- `linked_note_ids` trong pull Todo hiện bị bỏ qua.

Note upsert:

- `tag_ids` là full replacement.
- `note_links` là full replacement cho outgoing links của note.
- `linked_todo_ids` là full replacement cho Note-Todo links.

`note_links[]` cần:

```text
target_note_id   required
id               optional, Mobile fallback source->target
label            optional
created_at       optional
updated_at       optional
```

Self-heal sau tombstone:

- Todo tombstone xóa `todo_tags` và `note_todo_links` trỏ tới Todo.
- Note tombstone xóa `note_tags`, `note_todo_links`, incoming/outgoing
  `note_links`.

### 9.7 Required pull fields

Back-end nên trả full canonical row. Các field tối thiểu mà converter hiện yêu
cầu:

| Entity | Required cho active row |
|---|---|
| user | `id`; nên có đầy đủ public fields/timestamps |
| tag | `id`, `name`, `created_at`, `updated_at` |
| todo | `id`, `title`, `created_at`, `updated_at` |
| note | `id`, `title`, `created_at`, `updated_at` |
| habit | `id`, `title`, `start_date`, `created_at`, `updated_at` |
| habit_log | `id`, `habit_id`, `log_date`, `created_at`, `updated_at` |
| checklist_category | `id`, `name`, `created_at`, `updated_at` |
| checklist_template | `id`, `title`, `created_at`, `updated_at` |
| checklist_template_order | `id`, `template_id`, `created_at`, `updated_at` |
| checklist_template_item | `id`, `template_id`, `title`, `created_at`, `updated_at` |
| checklist_run | `id`, `template_id`, `updated_at`; nên có `started_at` |
| checklist_run_item | `id`, `run_id`, `created_at`, `updated_at` |

## 10. LWW và conflict semantics

Pull dùng Last-Write-Wins chỉ khi local entity có pending operation:

```text
if local.updated_at >= server.updated_at:
    giữ local, không apply server row
else:
    apply server row, xóa pending ops của entity
```

So sánh hiện tại parse timestamp bằng `DateTime.parse` và quy về UTC. Back-end
vẫn nên dùng một format canonical duy nhất:

```text
YYYY-MM-DDTHH:mm:ss.SSSZ
```

Không nên trộn:

- `Z` và `+07:00`
- có/không có milliseconds
- số chữ số fractional seconds khác nhau

Nếu format khác nhau, lexical order có thể không còn là chronological order.

Pull tombstone dùng policy delete-wins: clear pending operations, apply
tombstone và dọn junction/subtree. Pending update không được phép resurrect row
ở cycle sau.

Push conflict luôn server-wins. `server_version` cần là full canonical entity,
không phải patch, vì Mobile upsert trực tiếp và một số converter cần field bắt
buộc.

## 11. Recurring Todo

Mobile hỗ trợ:

```text
recurrence_type            daily | weekly | custom | null
recurrence_interval        integer >= 1
recurrence_days_of_week    comma-separated ISO weekday, e.g. "1,3,5"
recurrence_end_date        YYYY-MM-DD inclusive
recurrence_template_id     root series ID hoặc null
```

Hai loại recurrence row:

- Root/template: `recurrence_type != null`,
  `recurrence_template_id == null`.
- Real occurrence: `recurrence_template_id != null`; occurrence mới sau khi
  complete vẫn giữ recurrence fields.

Mobile từng có legacy local projections:

- `recurrence_template_id != null`
- `recurrence_type == null`
- chưa hoàn thành

Các projection này bị cleanup và không được push.

Khi complete local-first:

1. Todo hiện tại thành done và enqueue update.
2. Nếu có `habit_id`, Mobile có thể cập nhật habit-log projection local.
3. Mobile materialize đúng một next occurrence.
4. Mobile snapshot và clone toàn bộ active subtask tree parent-before-child,
   remap `parent_id` và internal `trigger_after_todo_id`, copy tags/metadata,
   reset runtime state.
5. Parent và descendants được ghi trong một transaction và enqueue create
   parent-before-child.

Khi pull thấy server occurrence cùng `(recurrence_template_id,
scheduled_date)` nhưng khác ID:

- Mobile thu thập và purge toàn bộ local occurrence subtree cũ.
- Xóa pending operations, `todo_tags` và Note-Todo junctions của cả subtree.
- Apply canonical parent và descendants server theo topological order.

Back-end cần:

- Duy trì uniqueness theo series/date hoặc trả conflict canonical.
- Không tạo nhiều active occurrence cho cùng series/date.
- Hiểu `delete_scope = this|future|all`.
- Với `future`, đồng bộ recurrence end date/cutoff nhất quán.
- Trả tombstone cho toàn bộ row bị ảnh hưởng hoặc trả một canonical model mà
  Mobile có thể tái dựng chính xác.

## 12. Habit và Todo-Habit projection

Todo có nullable `habit_id`.

Khi Todo local-first được complete, nếu Todo:

- có `habit_id`
- có `scheduled_date`
- có `completed_at`

Mobile tính trạng thái habit của ngày từ tất cả Todo live cùng habit/date. Nếu
tất cả đã done đúng hạn, Mobile cập nhật/tạo habit log local.

Projection này hiện không enqueue habit-log operation trong
`applyTodoCompletionProjection`; nó chủ yếu cập nhật UI/local cache. Todo update
vẫn được push. Back-end cần tự tính hoặc duy trì cùng semantic nếu Todo-Habit
link là business rule chính thức.

Nếu back-end trả `invalid_habit` cho Todo push, Mobile tự clear `habit_id` và
retry.

Streak:

- Mobile derive tạm từ local logs.
- Pull habit có thể cập nhật cached `current_streak`, `longest_streak`.
- Habit push không gửi hai field streak.

## 13. Checklist semantics

System category/template:

- Mobile coi `is_system = true` là read-only.
- Category update/delete bị chặn ở repository.
- Worker cũng drop queued update/delete system category/template.
- Back-end vẫn phải enforce và trả `read_only`.

Template order:

- User order nằm ở entity `checklist_template_order`.
- `template.sort_order` là fallback/default.
- Pull cần trả cả templates và per-user order rows.

Run:

- Mobile start run local-first từ cached template/items.
- Tạo một `checklist_run` và nhiều `checklist_run_item`.
- Run item payload không chứa snapshot title/required/position.
- Pull run item cố giữ snapshot cũ hoặc fallback sang template item nếu server
  không trả denormalized fields.

Back-end nên đảm bảo template item tồn tại trước khi xử lý run item create, hoặc
trả `bad_input` có diagnostic rõ.

## 14. Mức độ local-first theo module

| Module/action | Hiện trạng |
|---|---|
| Todo create/edit/complete/uncomplete/delete | Local-first trong UI chính |
| Todo tags | Local-first/full replacement khi offline hoặc UI edit |
| Todo mark frog/classify/move helper | REST-only, nhưng UI chính thường dùng generic local update |
| Tag list | REST-first, local fallback |
| Tag create từ Todo selector | Local-first |
| Tag create/update/delete API chung | REST-first, fallback offline |
| Habit list/detail | REST-first, cache Drift |
| Habit create | REST-first, fallback offline |
| Habit edit trong UI | Local-first |
| Habit archive/unarchive | REST-only |
| Habit delete | REST-first, fallback offline |
| Habit log/patch/delete | Local-first |
| Checklist category read | REST-first, local fallback |
| Checklist category create/update | Local-first |
| Checklist category delete | REST-first, fallback offline |
| Checklist template list/detail | REST-first, local fallback |
| Checklist template create | Local-first |
| Checklist template title/category update | REST-only |
| Checklist template delete | REST-only |
| Template item create/update/delete/reorder | Local-first |
| Template reorder | Local-first qua `checklist_template_order` |
| Checklist run start/progress/complete/abandon | Local-first |
| Checklist run delete | REST-only |
| Notes CRUD/relations/tags | Local-first |
| Dashboard | Local-first read snapshot + REST refresh |
| Reminders/settings notification | Local-only, không sync |

## 15. Các vấn đề/rủi ro phát hiện

### Critical: cursor/outbox không theo user - Đã xử lý

`last_synced_at` là một key global. `sync_queue` cũng không có `user_id`.
Logout chỉ xóa secure token/user, không xóa database, cursor hoặc outbox.

Hậu quả khi user A logout rồi user B login trên cùng thiết bị:

- User B có thể dùng cursor của user A và bỏ lỡ initial pull.
- Pending operations của user A có thể được push bằng token user B.
- Local cache của A vẫn tồn tại.
- Một số query có filter current user, nhưng Tags/Notes/Checklist không đồng
  đều.

Đây là lỗi Mobile cần sửa. Back-end bắt buộc phải kiểm tra ownership theo JWT để
ngăn cross-account write.

### Critical: ID remap chưa hoàn chỉnh

Mobile sinh UUID v7 và kỳ vọng server giữ ID.

Nếu server đổi ID:

- `applied`: Mobile bỏ qua `server_version`, không remap.
- `conflict`: Mobile chỉ remap pending JSON references chung.
- Local DB foreign references chỉ được xử lý riêng cho tag; habit log chỉ
  tombstone old row.
- Todo, Habit, Checklist entity ID remap có thể để lại old row và FK logic bị
  gãy.

Khuyến nghị back-end: preserve client-generated ID cho mọi create.

### High: Todo update có thể xóa Note relations - Đã xử lý

Todo payload luôn có `linked_note_ids`, nhưng các enqueue path hiện truyền
`[]`. Nếu back-end dùng full replacement, relation sẽ bị xóa ngoài ý muốn.

Cần thống nhất một trong ba hướng:

1. Mobile đọc relation thật trước khi enqueue.
2. Mobile bỏ field khi không có ý định sửa relation.
3. Back-end bỏ qua `linked_note_ids` trong Todo sync và chỉ quản lý quan hệ từ
   Note payload/REST endpoints.

Hướng 2 hoặc 3 an toàn hơn cho contract patch-like.

### High: tombstone và pending local write chưa có policy rõ - Đã xử lý

Pull tombstone luôn thắng local row nhưng không clear pending op. Sau đó pending
update/delete có thể tiếp tục push trên entity đã tombstone.

Cần định nghĩa:

- delete-wins
- update-resurrects
- hay compare `updated_at`

Hiện code không thực hiện nhất quán một trong ba.

### High: pull không atomic và không bảo đảm parent-before-child trong array - Đã xử lý

Nếu apply record thứ N lỗi:

- Record 1..N-1 đã ghi local.
- `last_synced_at` chưa đổi.
- Lần sau pull lại và upsert idempotently.

Điều này thường phục hồi được, nhưng UI có thể quan sát state partial. Back-end
nên trả dữ liệu idempotent và parent-first.

### High: retry error vĩnh viễn, diagnostic UI yếu - Đã xử lý ở mức outbox diagnostic

Path đang dùng `markFailedRetryable`, không dùng hàm có max retry. `bad_input`,
`forbidden`, `not_found` có thể retry vô hạn mỗi tối đa 5 phút.

Không có cột `failed_reason` trong outbox. UI không hiển thị operation nào lỗi,
chỉ hiện icon sync problem.

Back-end nên trả error code ổn định, nhưng Mobile vẫn cần dead-letter/diagnostic
UI.

### High: thiếu integration test cho SyncWorker - Đã bổ sung

Test hiện xác nhận:

- request operation shape
- bool/timestamp/server-only field payload
- Todo recurrence delete scopes
- local recurrence DB behavior

Chưa có test mock HTTP + Drift cho:

- pull đủ 12 arrays
- last cursor chỉ save sau apply
- conflict/server_version
- ID remap
- tombstone
- result missing/malformed
- auth 401
- batch >100
- relation reconciliation

### Medium: timestamp LWW so sánh bằng String - Đã xử lý

Back-end phải canonicalize timestamps cho tới khi Mobile đổi sang parse
`DateTime`.

### Medium: thiếu pull key bị coi là empty - Đã xử lý

Schema drift ở back-end có thể bị che giấu. Nên luôn trả đủ 12 key và Mobile nên
validate.

### Medium: User pull không cập nhật AuthStorage

`changes.users` được ghi Drift nhưng cached user trong secure storage không đổi.
UI profile có thể tiếp tục hiển thị thông tin cũ.

### Medium: Notes có local schema nhưng chưa offline-first

Back-end pull Notes có tác dụng cache dữ liệu, nhưng Notes UI không đọc cache và
Notes write không enqueue. Không nên coi Notes là đã hỗ trợ offline chỉ vì
SyncWorker có mapper.

### Medium: active `applied` response không được reconcile

Nếu server normalize field, set timestamp khác, hoặc sửa payload nhưng chỉ trả
`applied`, Mobile không apply canonical row ngay; phải chờ pull kế tiếp.

Khuyến nghị back-end:

- Preserve ID.
- Đảm bảo changed row xuất hiện ở pull ngay sau push.
- Hoặc Mobile cần hỗ trợ `server_version` trong `applied`.

### Low: source comments/documentation có phần stale - Đã cập nhật

Ví dụ comment đầu `TodosRepository` nói REST success enqueue queue, nhưng code
thực tế không enqueue khi REST đã thành công. `AGENTS.md` cũng ghi schemaVersion
6 trong một đoạn, trong khi source hiện là 10.

## 16. Contract back-end được khuyến nghị

### 16.1 Create/update/delete

- Accept client UUID v7 và preserve ID.
- Create phải idempotent theo `(user_id, entity_type, id)`.
- Update/delete unknown ID cần error code ổn định.
- Delete unknown ID từ create-then-delete offline nên có thể trả `applied`
  idempotently.
- Validate owner bằng JWT.
- Ignore/validate client `user_id`.
- Use server transaction per operation.
- Update `updated_at` trên mọi mutation, kể cả relation replacement.
- Soft delete bằng `deleted_at`, không làm tombstone biến mất khỏi delta.

### 16.2 Push result

Mỗi input operation trả đúng một result:

```json
{
  "id": "<input payload.id>",
  "status": "applied|conflict|error",
  "server_version": {},
  "error": "..."
}
```

- Không đổi `results[].id` thành server ID.
- `conflict` bắt buộc full `server_version`.
- `error` bắt buộc stable machine-readable code.
- Có thể giữ thứ tự result giống request dù Mobile hiện match bằng ID.

### 16.3 Pull

- Scope theo JWT.
- Trả đủ 12 arrays.
- Trả mọi row có mutation sau cursor, gồm tombstone.
- Full canonical relation arrays khi row relation thay đổi.
- Parent-first trong `todos`.
- Canonical UTC timestamps.
- Stable snapshot `server_time`.
- Không phân trang ngầm nếu response không có continuation cursor.

### 16.4 Conflict policy

Khuyến nghị thống nhất:

- Compare canonical `updated_at`.
- Nếu server mới hơn: `conflict + full server_version`.
- Nếu operation đã được apply trước đó: `applied` idempotent.
- Với unique semantic như tag name hoặc habit log `(habit_id, log_date)`, trả
  canonical existing row trong `conflict`.
- Với system checklist update/delete: `error/read_only`.

## 17. Việc phía Mobile nên sửa

Ưu tiên đề xuất:

1. Scope database/cursor/outbox theo authenticated user hoặc reset toàn bộ local
   sync state khi đổi account.
2. Thêm `user_id` vào `sync_queue` và cursor key theo user.
3. Sửa Todo relation payload để không gửi `linked_note_ids: []` ngoài ý muốn.
4. Hoàn thiện ID remap cho mọi entity và cả `applied`.
5. Định nghĩa rõ tombstone-vs-pending conflict.
6. Apply pull trong transaction; tách parent/child/relations/tombstones rõ.
7. Parse DateTime khi LWW, không compare String.
8. Thêm dead-letter state và UI diagnostic cho permanent errors.
9. Validate đủ 12 pull keys.
10. Thêm SyncWorker integration tests với fake Dio và in-memory Drift.
11. Hoàn thiện Notes local-first hoặc bỏ kỳ vọng Notes write khỏi sync contract.
    Đã hoàn thành ngày 2026-06-26.
12. Cập nhật AuthStorage khi pull user canonical.

## 18. Verification đã chạy trong audit

Lệnh:

```bash
flutter analyze
flutter test --concurrency=1
```

Kết quả ngày 2026-06-24:

- `flutter analyze`: pass, không có issue.
- Toàn bộ test suite: pass, 69 tests.
- Nhóm test sync/recurrence/local DB: pass, 17 tests.

Giới hạn:

- Không chạy live API với account/token trong audit này.
- Không có integration test trực tiếp cho GET/POST sync.
- Không kiểm chứng schema/implementation back-end; các yêu cầu phía back-end
  trong báo cáo được suy ra từ source Mobile.

## 19. Checklist đối chứng cho Codex back-end

Back-end nên trả lời/chứng minh từng mục:

- [ ] `/api/v1/sync/changes` và `/api/v1/sync/push` bắt buộc Bearer JWT.
- [ ] Pull scope hoàn toàn bằng JWT, không bằng client `user_id`.
- [ ] Pull trả đủ 12 arrays.
- [ ] `server_time` là canonical UTC snapshot boundary.
- [ ] Tombstone không bị lọc khỏi delta.
- [ ] Client UUID được preserve cho mọi create.
- [ ] Push trả đúng một result cho mỗi operation và dùng input ID.
- [ ] Create/delete là idempotent.
- [ ] Conflict trả full `server_version`.
- [ ] System category/template update/delete trả `read_only`.
- [ ] `current_streak`, `longest_streak`, `is_system`, `times_used`,
      `last_used_at` là server-only đúng như Mobile đang giả định.
- [ ] Todo parent/subtask validation khớp các field Mobile ép null.
- [ ] Recurrence và `delete_scope` khớp semantic Mobile.
- [ ] Tag uniqueness/resurrection được định nghĩa.
- [ ] Habit log uniqueness theo `(user, habit_id, log_date)` được định nghĩa.
- [ ] Note relation replacement semantics được xác nhận.
- [ ] Có quyết định cụ thể cho `linked_note_ids: []` trong Todo payload.
- [ ] Có quyết định cụ thể cho tombstone gặp pending local update.
- [ ] Bad input/forbidden/not found dùng stable error codes.

## 20. File reference nhanh

- Sync orchestration: `lib/sync/sync_worker.dart`
- Wire payload: `lib/sync/sync_payload.dart`
- Queue/cursor: `lib/data/local/dao/sync_dao.dart`
- Schema: `lib/data/local/tables.dart`
- Migration/version: `lib/data/local/database.dart`
- Sync auth client: `lib/data/remote/api_client_dio.dart`
- Todo local-first: `lib/data/todos_repository.dart`
- Habit local-first: `lib/data/habits_repository.dart`
- Checklist local-first: `lib/data/checklists_repository.dart`
- Tag fallback/local-first: `lib/data/tags_repository.dart`
- Notes local-first: `lib/data/notes_repository.dart`
- Dashboard local snapshot: `lib/data/dashboard_repository.dart`
- Payload tests: `test/sync_payload_test.dart`
- Recurrence delete tests: `test/todo_delete_scope_test.dart`
