class UsagePoint {
  const UsagePoint({
    required this.date,
    required this.label,
    required this.rxBytes,
    required this.txBytes,
  });

  final String date;
  final String label;
  final int rxBytes;
  final int txBytes;

  int get totalBytes => rxBytes + txBytes;

  factory UsagePoint.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return UsagePoint(
      date: '${json['date'] ?? ''}',
      label: '${json['label'] ?? ''}',
      rxBytes: asInt(json['rx_bytes']),
      txBytes: asInt(json['tx_bytes']),
    );
  }
}

class UsageSeries {
  const UsageSeries({
    required this.range,
    required this.points,
    required this.totalRxBytes,
    required this.totalTxBytes,
  });

  final String range;
  final List<UsagePoint> points;
  final int totalRxBytes;
  final int totalTxBytes;

  int get totalBytes => totalRxBytes + totalTxBytes;

  factory UsageSeries.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    final raw = json['points'];
    final points = <UsagePoint>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          points.add(
            UsagePoint.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return UsageSeries(
      range: '${json['range'] ?? ''}',
      points: points,
      totalRxBytes: asInt(json['total_rx_bytes']),
      totalTxBytes: asInt(json['total_tx_bytes']),
    );
  }

  static const empty = UsageSeries(
    range: '',
    points: [],
    totalRxBytes: 0,
    totalTxBytes: 0,
  );

  /// Zero-filled buckets so the chart always has a drawable line.
  ///
  /// [range]: `24h` | `7d` | `30d` | `all`
  static UsageSeries scaffold({
    required String range,
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc();
    switch (range) {
      case '24h':
        final end = DateTime.utc(
          clock.year,
          clock.month,
          clock.day,
          clock.hour,
        ).add(const Duration(hours: 1));
        final start = end.subtract(const Duration(hours: 24));
        final points = <UsagePoint>[];
        for (var t = start; t.isBefore(end); t = t.add(const Duration(hours: 1))) {
          final hh = t.hour.toString().padLeft(2, '0');
          points.add(
            UsagePoint(
              date: '${t.toIso8601String().substring(0, 13)}:00:00',
              label: '$hh:00',
              rxBytes: 0,
              txBytes: 0,
            ),
          );
        }
        return UsageSeries(
          range: '24h',
          points: points,
          totalRxBytes: 0,
          totalTxBytes: 0,
        );
      case '30d':
        return _dailyScaffold(range: '30d', days: 30, clock: clock);
      case 'all':
        return _dailyScaffold(range: 'all', days: 365, clock: clock);
      case '7d':
      default:
        return _dailyScaffold(range: '7d', days: 7, clock: clock);
    }
  }

  static UsageSeries _dailyScaffold({
    required String range,
    required int days,
    required DateTime clock,
  }) {
    final end = DateTime.utc(clock.year, clock.month, clock.day)
        .add(const Duration(days: 1));
    final start = end.subtract(Duration(days: days));
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final points = <UsagePoint>[];
    for (var t = start; t.isBefore(end); t = t.add(const Duration(days: 1))) {
      final y = t.year.toString().padLeft(4, '0');
      final m = t.month.toString().padLeft(2, '0');
      final d = t.day.toString().padLeft(2, '0');
      points.add(
        UsagePoint(
          date: '$y-$m-$d',
          label: weekdays[t.weekday - 1],
          rxBytes: 0,
          txBytes: 0,
        ),
      );
    }
    return UsageSeries(
      range: range,
      points: points,
      totalRxBytes: 0,
      totalTxBytes: 0,
    );
  }
}
