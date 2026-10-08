import 'package:flutter/widgets.dart';

/// Báo cho app biết trang chi tiết của todo nào đang là route trên cùng.
///
/// Dùng để quyết định có cần mở lại trang chi tiết sau khi hủy bấm giờ hay
/// không: nếu trang chi tiết của đúng todo đó đang nằm ngay dưới màn Focus thì
/// chỉ cần đóng màn Focus, tránh chồng hai trang chi tiết giống nhau.
class TodoDetailRouteTracker extends StatefulWidget {
  final String todoId;
  final Widget child;

  const TodoDetailRouteTracker({
    super.key,
    required this.todoId,
    required this.child,
  });

  /// Todo của trang chi tiết đang là route trên cùng, `null` nếu không có.
  static String? get currentTodoId => _TrackerState._current?.widget.todoId;

  @override
  State<TodoDetailRouteTracker> createState() => _TrackerState();
}

class _TrackerState extends State<TodoDetailRouteTracker> {
  static _TrackerState? _current;

  // `isCurrent` đổi sẽ làm ModalRoute thông báo lại cho dependent nên
  // didChangeDependencies chạy mỗi khi có route khác được push/pop lên trên.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      _current = this;
    } else if (identical(_current, this)) {
      _current = null;
    }
  }

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
