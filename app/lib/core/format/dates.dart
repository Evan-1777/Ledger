import 'package:intl/intl.dart';

final _monthDay = DateFormat('M月d日', 'zh_CN');
final _fullDate = DateFormat('yyyy年M月d日', 'zh_CN');
final _weekday = DateFormat('EEE', 'zh_CN');
final _time = DateFormat('HH:mm', 'zh_CN');
final _month = DateFormat('yyyy 年 M 月', 'zh_CN');
final _dateParam = DateFormat('yyyy-MM-dd');

String formatMonth(DateTime date) => _month.format(date);
String formatDateParam(DateTime date) => _dateParam.format(date);
String formatMonthDay(DateTime date) => _monthDay.format(date);
String formatTime(DateTime date) => _time.format(date);
String formatWeekday(DateTime date) => _weekday.format(date);

String formatDayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return date.year == now.year
      ? _monthDay.format(date)
      : _fullDate.format(date);
}
