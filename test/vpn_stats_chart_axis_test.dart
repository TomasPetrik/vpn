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

  test('12-month ticks label each month boundary', () {
    final points = UsageSeries.scaffold(
      range: 'all',
      now: DateTime.utc(2026, 11, 19, 11),
    ).points;
    final ticks = VpnStatsChartAxis.ticks(
      points: points,
      period: VpnStatsChartPeriod.months12,
    );
    expect(ticks, isNotEmpty);
    expect(ticks.length, inInclusiveRange(12, 13));
    expect(ticks.map((t) => t.label).toSet(), containsAll(['Jan', 'Nov']));
  });
}
