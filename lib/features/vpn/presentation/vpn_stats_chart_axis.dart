import '../domain/usage_series.dart';

enum VpnStatsChartPeriod { hours24, days7, days30, months12 }

class VpnStatsChartTick {
  const VpnStatsChartTick({required this.index, required this.label});

  final int index;
  final String label;
}

/// Sparse x-axis ticks positioned under bucket centers.
class VpnStatsChartAxis {
  const VpnStatsChartAxis._();

  static List<VpnStatsChartTick> ticks({
    required List<UsagePoint> points,
    required VpnStatsChartPeriod period,
  }) {
    if (points.isEmpty) {
      return const [];
    }
    switch (period) {
      case VpnStatsChartPeriod.hours24:
        final out = <VpnStatsChartTick>[];
        for (var i = 0; i < points.length; i++) {
          if (i % 6 != 0 && i != points.length - 1) {
            continue;
          }
          out.add(VpnStatsChartTick(index: i, label: hourLabel(points[i])));
        }
        return out;
      case VpnStatsChartPeriod.days7:
        return [
          for (var i = 0; i < points.length; i++)
            VpnStatsChartTick(
              index: i,
              label: points[i].label.isNotEmpty
                  ? points[i].label
                  : weekdayOf(points[i]),
            ),
        ];
      case VpnStatsChartPeriod.days30:
        final step = (points.length / 5).ceil().clamp(1, points.length);
        final out = <VpnStatsChartTick>[];
        for (var i = 0; i < points.length; i++) {
          if (i % step != 0 && i != points.length - 1) {
            continue;
          }
          out.add(VpnStatsChartTick(index: i, label: dayMonthLabel(points[i])));
        }
        return out;
      case VpnStatsChartPeriod.months12:
        // Monthly series: one label per bucket. Daily legacy: month boundaries.
        if (points.length <= 14) {
          return [
            for (var i = 0; i < points.length; i++)
              VpnStatsChartTick(
                index: i,
                label: points[i].label.isNotEmpty
                    ? points[i].label
                    : monthTickLabel(points[i]),
              ),
          ];
        }
        final out = <VpnStatsChartTick>[];
        var lastMonth = -1;
        for (var i = 0; i < points.length; i++) {
          final month = monthOf(points[i]);
          if (month == null) {
            continue;
          }
          if (i == 0 || month != lastMonth) {
            out.add(VpnStatsChartTick(index: i, label: monthLabel(month)));
            lastMonth = month;
          }
        }
        return out;
    }
  }

  static String monthTickLabel(UsagePoint point) {
    final month = monthOf(point);
    if (month == null) {
      return point.label;
    }
    return monthLabel(month);
  }

  static double tickLeft({
    required int index,
    required int count,
    required double width,
    required double labelWidth,
  }) {
    if (count <= 0 || width <= 0) {
      return 0;
    }
    final center = (index + 0.5) / count * width;
    final maxLeft = width - labelWidth;
    final left = center - labelWidth / 2;
    if (maxLeft <= 0) {
      return 0;
    }
    if (left < 0) {
      return 0;
    }
    if (left > maxLeft) {
      return maxLeft;
    }
    return left;
  }

  static String hourLabel(UsagePoint point) {
    final fromLabel = RegExp(r'^(\d{1,2})').firstMatch(point.label);
    if (fromLabel != null) {
      final hour = int.parse(fromLabel.group(1)!);
      return '${hour.toString().padLeft(2, '0')}:00';
    }
    final fromDate = RegExp(r'(\d{2}):\d{2}').firstMatch(point.date);
    if (fromDate != null) {
      return '${fromDate.group(1)}:00';
    }
    return point.label;
  }

  static String dayMonthLabel(UsagePoint point) {
    final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(point.date);
    if (match != null) {
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      return '$day${monthLabel(month)}';
    }
    return point.label;
  }

  static String weekdayOf(UsagePoint point) {
    final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(point.date);
    if (match != null) {
      final dt = DateTime.utc(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    }
    return point.label;
  }

  static int? monthOf(UsagePoint point) {
    final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(point.date);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(2)!);
  }

  static String monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month < 1 || month > 12) {
      return '$month';
    }
    return months[month - 1];
  }

  /// Human-readable bucket title for scrub tooltips.
  static String detailTitle({
    required UsagePoint point,
    required VpnStatsChartPeriod period,
  }) {
    switch (period) {
      case VpnStatsChartPeriod.hours24:
        return hourLabel(point);
      case VpnStatsChartPeriod.days7:
        final weekday =
            point.label.isNotEmpty ? point.label : weekdayOf(point);
        final day = dayMonthLabel(point);
        return day == point.label ? weekday : '$weekday · $day';
      case VpnStatsChartPeriod.days30:
        return dayMonthLabel(point);
      case VpnStatsChartPeriod.months12:
        return monthDetailTitle(point);
    }
  }

  static String monthDetailTitle(UsagePoint point) {
    final match = RegExp(r'(\d{4})-(\d{2})').firstMatch(point.date);
    if (match != null) {
      final year = match.group(1)!;
      final month = int.parse(match.group(2)!);
      return '${monthLabel(month)} $year';
    }
    if (point.label.isNotEmpty) {
      return point.label;
    }
    return point.date;
  }

  /// Map a touch X (in chart width) to the nearest series index (line chart).
  static int indexAtX({
    required double x,
    required double width,
    required int count,
  }) {
    if (count <= 1 || width <= 0) {
      return 0;
    }
    final t = (x / width).clamp(0.0, 1.0);
    return (t * (count - 1)).round().clamp(0, count - 1);
  }

  /// Map a touch X to a bar slot (equal-width columns).
  static int indexAtBarX({
    required double x,
    required double width,
    required int count,
  }) {
    if (count <= 0 || width <= 0) {
      return 0;
    }
    final t = (x / width).clamp(0.0, 0.999999);
    return (t * count).floor().clamp(0, count - 1);
  }
}
