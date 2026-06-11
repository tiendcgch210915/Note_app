import '../models/dashboard.dart';
import '../utils/date_utils.dart';
import '../utils/json_utils.dart';
import 'api_client.dart';

/// Repository cho Group D — Dashboard. 3 endpoint F-D1/F-D2/F-D3.
class DashboardRepository {
  DashboardRepository._();
  static final DashboardRepository instance = DashboardRepository._();
  final ApiClient _client = ApiClient.instance;

  /// F-D1 Today summary.
  Future<DashboardSnapshot> today({DateTime? date}) async {
    final localDate = AppDateUtils.dateOnly(date ?? DateTime.now());
    final resp = await _client.get(
      '/dashboard/today',
      query: {'date': formatDateOnly(localDate)},
    );
    return DashboardSnapshot.fromJson(resp as Map<String, dynamic>);
  }

  /// F-D2 Eisenhower detail (chứa by_quadrant preview todos).
  Future<EisenhowerDetail> eisenhower({DateTime? date}) async {
    final localDate = AppDateUtils.dateOnly(date ?? DateTime.now());
    final resp = await _client.get(
      '/dashboard/eisenhower',
      query: {'date': formatDateOnly(localDate)},
    );
    return EisenhowerDetail.fromJson(resp as Map<String, dynamic>);
  }

  /// F-D3 Calendar overview.
  Future<Map<DateTime, CalendarDay>> calendar({
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _client.get(
      '/dashboard/calendar',
      query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
    );
    final daysMap =
        (resp as Map<String, dynamic>)['days'] as Map<String, dynamic>? ?? {};
    final result = <DateTime, CalendarDay>{};
    daysMap.forEach((dateStr, value) {
      result[jsonDateOnly(dateStr)] = CalendarDay.fromJson(
        value as Map<String, dynamic>,
      );
    });
    return result;
  }
}
