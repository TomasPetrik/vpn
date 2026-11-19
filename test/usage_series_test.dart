import 'package:flutter_test/flutter_test.dart';
import 'package:ru_eu_vpn/features/vpn/domain/usage_series.dart';

void main() {
  test('UsageSeries parses backend payload', () {
    final series = UsageSeries.fromJson({
      'range': '7d',
      'total_rx_bytes': 1500,
      'total_tx_bytes': 500,
      'points': [
        {
          'date': '2026-11-17',
          'label': 'Tue',
          'rx_bytes': 1000,
          'tx_bytes': 200,
        },
        {
          'date': '2026-11-18',
          'label': 'Wed',
          'rx_bytes': 500,
          'tx_bytes': 300,
        },
      ],
    });

    expect(series.range, '7d');
    expect(series.totalBytes, 2000);
    expect(series.points, hasLength(2));
    expect(series.points.first.label, 'Tue');
    expect(series.points.last.rxBytes, 500);
  });

  test('scaffold builds 24 hourly and 7 daily buckets', () {
    final day = UsageSeries.scaffold(
      range: '7d',
      now: DateTime.utc(2026, 11, 18, 15),
    );
    expect(day.points, hasLength(7));
    expect(day.totalBytes, 0);

    final hours = UsageSeries.scaffold(
      range: '24h',
      now: DateTime.utc(2026, 11, 18, 15),
    );
    expect(hours.points, hasLength(24));
  });

  test('scaffold all builds 12 monthly buckets', () {
    final months = UsageSeries.scaffold(
      range: 'all',
      now: DateTime.utc(2026, 11, 19, 11),
    );
    expect(months.points, hasLength(12));
    expect(months.points.first.date, '2025-12-01');
    expect(months.points.first.label, 'Dec');
    expect(months.points.last.date, '2026-11-01');
    expect(months.points.last.label, 'Nov');
  });

  test('ensureChartGranularity rolls daily all points into months', () {
    final daily = UsageSeries.scaffold(
      range: 'all',
      now: DateTime.utc(2026, 11, 19, 11),
    );
    // Simulate legacy daily payload by expanding scaffold months is already monthly;
    // build a fake dense daily series instead.
    final dense = UsageSeries(
      range: 'all',
      totalRxBytes: 300,
      totalTxBytes: 30,
      points: [
        for (var i = 0; i < 40; i++)
          UsagePoint(
            date: DateTime.utc(2026, 10, 1).add(Duration(days: i)).toIso8601String().substring(0, 10),
            label: 'd',
            rxBytes: 10,
            txBytes: 1,
          ),
      ],
    );
    final rolled = dense.ensureChartGranularity();
    expect(rolled.points.length, lessThanOrEqualTo(3));
    expect(rolled.points.length, greaterThanOrEqualTo(2));
    expect(
      rolled.points.fold<int>(0, (sum, p) => sum + p.rxBytes),
      400,
    );
    expect(daily.ensureChartGranularity().points, hasLength(12));
  });
}
