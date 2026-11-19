import 'package:flutter_test/flutter_test.dart';
import 'package:ru_eu_vpn/features/vpn/domain/usage_series.dart';
import 'package:ru_eu_vpn/features/vpn/presentation/vpn_stats_chart_axis.dart';

void main() {
  test('24h ticks every 6 hours as HH:00', () {
    final points = UsageSeries.scaffold(
      range: '24h',
      now: DateTime.utc(2026, 11, 19, 11),
    ).points;
    final ticks = VpnStatsChartAxis.ticks(
      points: points,
      period: VpnStatsChartPeriod.hours24,
    );
    expect(ticks, isNotEmpty);
    expect(ticks.first.label, matches(RegExp(r'^\d{2}:00$')));
    expect(ticks.map((t) => t.label).toSet().length, greaterThan(1));
  });

  test('30d ticks use day + month and stay sparse', () {
    final points = UsageSeries.scaffold(
      range: '30d',
      now: DateTime.utc(2026, 11, 19, 11),
    ).points;
    final ticks = VpnStatsChartAxis.ticks(
      points: points,
      period: VpnStatsChartPeriod.days30,
    );
    expect(ticks.length, inInclusiveRange(5, 7));
    expect(ticks.first.label, matches(RegExp(r'^\d{1,2}[A-Z][a-z]{2}$')));
    // Must not be a clipped day-only digit stream.
    expect(ticks.every((t) => t.label.length >= 4), isTrue);
  });

  test('12-month ticks label each monthly bucket', () {
    final points = UsageSeries.scaffold(
      range: 'all',
      now: DateTime.utc(2026, 11, 19, 11),
    ).points;
    final ticks = VpnStatsChartAxis.ticks(
      points: points,
      period: VpnStatsChartPeriod.months12,
    );
    expect(ticks, hasLength(12));
    expect(ticks.first.label, 'Dec');
    expect(ticks.last.label, 'Nov');
    expect(
      VpnStatsChartAxis.detailTitle(
        point: points.last,
        period: VpnStatsChartPeriod.months12,
      ),
      'Nov 2026',
    );
  });

  test('indexAtX maps edges and midpoint to series buckets', () {
    expect(
      VpnStatsChartAxis.indexAtX(x: 0, width: 100, count: 24),
      0,
    );
    expect(
      VpnStatsChartAxis.indexAtX(x: 100, width: 100, count: 24),
      23,
    );
    expect(
      VpnStatsChartAxis.indexAtX(x: 50, width: 100, count: 11),
      5,
    );
  });

  test('indexAtBarX maps equal-width column slots', () {
    expect(
      VpnStatsChartAxis.indexAtBarX(x: 0, width: 120, count: 12),
      0,
    );
    expect(
      VpnStatsChartAxis.indexAtBarX(x: 10, width: 120, count: 12),
      1,
    );
    expect(
      VpnStatsChartAxis.indexAtBarX(x: 119, width: 120, count: 12),
      11,
    );
  });

  test('detailTitle formats hour and day buckets', () {
    expect(
      VpnStatsChartAxis.detailTitle(
        point: const UsagePoint(
          date: '2026-11-19 14:00:00',
          label: '14:00',
          rxBytes: 1,
          txBytes: 2,
        ),
        period: VpnStatsChartPeriod.hours24,
      ),
      '14:00',
    );
    expect(
      VpnStatsChartAxis.detailTitle(
        point: const UsagePoint(
          date: '2026-11-19',
          label: 'Wed',
          rxBytes: 1,
          txBytes: 2,
        ),
        period: VpnStatsChartPeriod.days7,
      ),
      'Wed · 19Nov',
    );
  });
}
