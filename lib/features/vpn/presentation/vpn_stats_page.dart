import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';
import '../../device/domain/device_repository.dart';
import '../../device/domain/vpn_peer_config.dart';
import '../domain/usage_series.dart';
import 'home/country_flag.dart';
import 'vpn_connect_cubit.dart';
import 'vpn_stats_chart_axis.dart';
import 'vpn_stats_format.dart';

enum _StatsPeriod { today, days7, days30, all }

class VpnStatsPage extends StatefulWidget {
  const VpnStatsPage({super.key});

  @override
  State<VpnStatsPage> createState() => _VpnStatsPageState();
}

class _VpnStatsPageState extends State<VpnStatsPage> {
  _StatsPeriod _period = _StatsPeriod.days7;
  final Map<String, UsageSeries> _usageCache = {
    for (final range in const ['24h', '7d', '30d', 'all'])
      range: UsageSeries.scaffold(range: range),
  };
  final Set<String> _usageFetched = {};
  final Set<String> _usageInFlight = {};
  Timer? _liveUsageTimer;
  bool _wasConnected = false;

  UsageSeries get _usage =>
      _usageCache[_apiRange] ?? UsageSeries.scaffold(range: _apiRange);

  @override
  void initState() {
    super.initState();
    context.read<VpnConnectCubit>().refreshCommittedTotals();
    // Warm current + neighbors in the background (no spinner).
    unawaited(_ensureUsage(_apiRange));
    unawaited(_prefetchNeighbors(_apiRange));
    final connected = context.read<VpnConnectCubit>().state.isConnected;
    _wasConnected = connected;
    if (connected) {
      _startLiveUsageRefresh();
    }
  }

  @override
  void dispose() {
    _liveUsageTimer?.cancel();
    super.dispose();
  }

  void _syncLiveUsageRefresh(bool connected) {
    if (connected == _wasConnected) {
      return;
    }
    _wasConnected = connected;
    if (connected) {
      _startLiveUsageRefresh();
      unawaited(_ensureUsage(_apiRange, force: true));
    } else {
      _liveUsageTimer?.cancel();
      _liveUsageTimer = null;
      unawaited(_ensureUsage(_apiRange, force: true));
    }
  }

  void _startLiveUsageRefresh() {
    _liveUsageTimer?.cancel();
    // Backend SyncStats samples ~15s; refresh a bit faster so cards move.
    _liveUsageTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_ensureUsage(_apiRange, force: true));
    });
  }

  String get _apiRange => _rangeFor(_period);

  static String _rangeFor(_StatsPeriod period) => switch (period) {
        _StatsPeriod.today => '24h',
        _StatsPeriod.days7 => '7d',
        _StatsPeriod.days30 => '30d',
        _StatsPeriod.all => 'all',
      };

  void _selectPeriod(_StatsPeriod value) {
    if (value == _period) return;
    final range = _rangeFor(value);
    setState(() => _period = value);
    // Instant axis/scaffold swap from cache; refresh silently.
    unawaited(_ensureUsage(range));
    unawaited(_prefetchNeighbors(range));
  }

  Future<void> _prefetchNeighbors(String current) async {
    const order = ['24h', '7d', '30d', 'all'];
    final i = order.indexOf(current);
    if (i < 0) return;
    if (i > 0) unawaited(_ensureUsage(order[i - 1]));
    if (i < order.length - 1) unawaited(_ensureUsage(order[i + 1]));
  }

  Future<void> _loadUsage() => _ensureUsage(_apiRange, force: true);

  Future<void> _ensureUsage(String range, {bool force = false}) async {
    if (!force && _usageFetched.contains(range)) return;
    if (_usageInFlight.contains(range)) return;
    _usageInFlight.add(range);
    try {
      final series = await getIt<DeviceRepository>().usageSeries(range: range);
      if (!mounted) return;
      final normalized = series.ensureChartGranularity();
      final next = normalized.points.isEmpty
          ? UsageSeries.scaffold(range: range)
          : normalized;
      setState(() {
        _usageCache[range] = next;
        _usageFetched.add(range);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usageCache[range] ??= UsageSeries.scaffold(range: range);
      });
    } finally {
      _usageInFlight.remove(range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: SafeArea(
        child: BlocConsumer<VpnConnectCubit, VpnConnectState>(
          listenWhen: (prev, next) => prev.isConnected != next.isConnected,
          listener: (context, state) {
            _syncLiveUsageRefresh(state.isConnected);
          },
          builder: (context, state) {
            final overall = state.overallTotals;
            // Period cards prefer backend peer_stats (server WireGuard truth).
            // All-time while connected also lifts with local live counters so the
            // UI moves before the next SyncStats sample lands.
            final periodRx = _period == _StatsPeriod.all && state.isConnected
                ? math.max(_usage.totalRxBytes, overall.rxBytes)
                : _usage.totalRxBytes;
            final periodTx = _period == _StatsPeriod.all && state.isConnected
                ? math.max(_usage.totalTxBytes, overall.txBytes)
                : _usage.totalTxBytes;
            final totalBytes = periodRx + periodTx;
            final rxShare =
                totalBytes == 0 ? 0.0 : periodRx / totalBytes;
            final txShare =
                totalBytes == 0 ? 0.0 : periodTx / totalBytes;
            final days = switch (_period) {
              _StatsPeriod.today => 1,
              _StatsPeriod.days7 => 7,
              _StatsPeriod.days30 => 30,
              _StatsPeriod.all => math.max(1, overall.activeSeconds ~/ 86400),
            };
            final avgRxPerDay = periodRx / days;
            final avgTxPerDay = periodTx / days;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: CyberShieldColors.background,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Data & Analytics',
                                style: CyberShieldTheme.headlineSm().copyWith(
                                  fontSize: 24,
                                  height: 32 / 24,
                                  letterSpacing: -0.02 * 24,
                                ),
                              ),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: CyberShieldColors.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                tooltip: 'Refresh totals',
                                onPressed: () {
                                  context
                                      .read<VpnConnectCubit>()
                                      .refreshCommittedTotals();
                                  _usageFetched.remove(_apiRange);
                                  unawaited(_loadUsage());
                                },
                                icon: const Icon(Icons.refresh, size: 20),
                                color: CyberShieldColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _PeriodSelector(
                          period: _period,
                          onChanged: _selectPeriod,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Total Consumed',
                              icon: Icons.data_usage,
                              iconColor: CyberShieldColors.secondaryContainer,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _MetricValue(
                                    value: _splitBytes(totalBytes).$1,
                                    unit: _splitBytes(totalBytes).$2,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    state.isConnected
                                        ? 'Server usage · live tunnel'
                                        : 'Server-reported usage',
                                    style: CyberShieldTheme.bodySm(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MetricCard(
                              label: 'Time Shielded',
                              icon: Icons.timer_outlined,
                              iconColor: CyberShieldColors.primary,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DurationValue(
                                    seconds: overall.activeSeconds,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    state.isConnected
                                        ? 'Current tunnel active'
                                        : 'Across encrypted sessions',
                                    style: CyberShieldTheme.bodySm(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _TrafficShareCard(
                              label: 'Download',
                              icon: Icons.arrow_downward,
                              accent: CyberShieldColors.secondaryContainer,
                              bytes: periodRx,
                              share: rxShare,
                              avgPerDay: avgRxPerDay,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TrafficShareCard(
                              label: 'Upload',
                              icon: Icons.arrow_upward,
                              accent: CyberShieldColors.primary,
                              bytes: periodTx,
                              share: txShare,
                              avgPerDay: avgTxPerDay,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BandwidthPulseCard(
                        period: _period,
                        series: _usage,
                      ),
                      const SizedBox(height: 16),
                      _SessionLedger(
                        state: state,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static (String, String) _splitBytes(int bytes) {
    final formatted = VpnStatsFormat.bytes(bytes);
    final parts = formatted.split(' ');
    if (parts.length < 2) {
      return (formatted, '');
    }
    return (parts.first, parts.sublist(1).join(' '));
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.onChanged,
  });

  final _StatsPeriod period;
  final ValueChanged<_StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(_StatsPeriod value, String label) {
      final selected = period == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? CyberShieldColors.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: CyberShieldTheme.labelBadge(
                color: selected
                    ? Colors.white
                    : CyberShieldColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          tab(_StatsPeriod.today, '24h'),
          tab(_StatsPeriod.days7, '7 Days'),
          tab(_StatsPeriod.days30, '30 Days'),
          tab(_StatsPeriod.all, '12 Months'),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: CyberShieldTheme.labelBadge()),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: CyberShieldColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: CyberShieldTheme.metricStat()),
        const SizedBox(width: 4),
        Text(
          unit,
          style: CyberShieldTheme.labelCode(
            color: CyberShieldColors.secondaryContainer,
          ),
        ),
      ],
    );
  }
}

class _DurationValue extends StatelessWidget {
  const _DurationValue({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${h}h', style: CyberShieldTheme.metricStat()),
          TextSpan(
            text: ' ${m.toString().padLeft(2, '0')}m',
            style: CyberShieldTheme.headlineSm(
              color: CyberShieldColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficShareCard extends StatelessWidget {
  const _TrafficShareCard({
    required this.label,
    required this.icon,
    required this.accent,
    required this.bytes,
    required this.share,
    required this.avgPerDay,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final int bytes;
  final double share;
  final double avgPerDay;

  @override
  Widget build(BuildContext context) {
    final formatted = VpnStatsFormat.bytes(bytes);
    final parts = formatted.split(' ');
    final value = parts.first;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: CyberShieldTheme.labelBadge()),
              ),
              Icon(icon, size: 16, color: accent),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: CyberShieldTheme.headlineSm().copyWith(
                    fontSize: 24,
                    height: 32 / 24,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: CyberShieldTheme.labelCode(
                    color: CyberShieldColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: CyberShieldColors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Avg ${VpnStatsFormat.bytes(avgPerDay.round())}/d',
              style: CyberShieldTheme.labelCode(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandwidthPulseCard extends StatefulWidget {
  const _BandwidthPulseCard({
    required this.period,
    required this.series,
  });

  final _StatsPeriod period;
  final UsageSeries series;

  @override
  State<_BandwidthPulseCard> createState() => _BandwidthPulseCardState();
}

enum _PulseChartStyle { lines, columns }

class _BandwidthPulseCardState extends State<_BandwidthPulseCard> {
  int? _scrubIndex;
  _PulseChartStyle _style = _PulseChartStyle.lines;

  _StatsPeriod get period => widget.period;
  UsageSeries get series => widget.series;

  VpnStatsChartPeriod get _chartPeriod => switch (period) {
        _StatsPeriod.today => VpnStatsChartPeriod.hours24,
        _StatsPeriod.days7 => VpnStatsChartPeriod.days7,
        _StatsPeriod.days30 => VpnStatsChartPeriod.days30,
        _StatsPeriod.all => VpnStatsChartPeriod.months12,
      };

  @override
  void didUpdateWidget(covariant _BandwidthPulseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period ||
        oldWidget.series.range != widget.series.range ||
        oldWidget.series.points.length != widget.series.points.length) {
      _scrubIndex = null;
    } else if (_scrubIndex != null &&
        _scrubIndex! >= widget.series.points.length) {
      _scrubIndex = null;
    }
  }

  void _scrubAt(Offset local, double width) {
    final points = series.points;
    if (points.isEmpty || width <= 0) {
      return;
    }
    final next = _style == _PulseChartStyle.columns
        ? VpnStatsChartAxis.indexAtBarX(
            x: local.dx,
            width: width,
            count: points.length,
          )
        : VpnStatsChartAxis.indexAtX(
            x: local.dx,
            width: width,
            count: points.length,
          );
    if (next == _scrubIndex) {
      return;
    }
    setState(() => _scrubIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    final peakIndex = _peakIndex(points);
    final total = series.totalBytes;
    final scrub = (_scrubIndex != null &&
            _scrubIndex! >= 0 &&
            _scrubIndex! < points.length)
        ? points[_scrubIndex!]
        : null;
    final activeIndex = scrub != null ? _scrubIndex! : peakIndex;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bandwidth Pulse',
                      style: CyberShieldTheme.headlineSm(),
                    ),
                    Text(
                      switch (period) {
                        _StatsPeriod.today =>
                          'Hourly transfer · last 24 hours',
                        _StatsPeriod.days7 =>
                          'Daily transfer · last 7 days',
                        _StatsPeriod.days30 =>
                          'Daily transfer · last 30 days',
                        _StatsPeriod.all =>
                          'Monthly transfer · past 12 months',
                      },
                      style: CyberShieldTheme.bodySm(),
                    ),
                  ],
                ),
              ),
              _PulseStyleToggle(
                style: _style,
                onChanged: (next) => setState(() => _style = next),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberShieldColors.secondaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: CyberShieldColors.secondaryContainer
                          .withValues(alpha: 0.7),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text('Down', style: CyberShieldTheme.labelBadge()),
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberShieldColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Text('Up', style: CyberShieldTheme.labelBadge()),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: Builder(
              builder: (context) {
                final rxValues = [
                  for (final p in points) p.rxBytes.toDouble(),
                ];
                final txValues = [
                  for (final p in points) p.txBytes.toDouble(),
                ];
                var maxBytes = 0;
                for (final p in points) {
                  maxBytes = math.max(maxBytes, p.rxBytes);
                  maxBytes = math.max(maxBytes, p.txBytes);
                }
                final midBytes = maxBytes ~/ 2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 44,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final h = constraints.maxHeight;
                          // Match painter top/mid/baseline fractions.
                          const topFrac = 0.08;
                          const midFrac = 0.48;
                          const baseFrac = 0.88;
                          Text tick(String text) => Text(
                                text,
                                style: CyberShieldTheme.labelCode(
                                  color: CyberShieldColors.onSurfaceVariant,
                                ).copyWith(fontSize: 9),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              );
                          return Stack(
                            children: [
                              Positioned(
                                right: 6,
                                top: h * topFrac - 6,
                                child: tick(VpnStatsFormat.bytes(maxBytes)),
                              ),
                              Positioned(
                                right: 6,
                                top: h * midFrac - 6,
                                child: tick(VpnStatsFormat.bytes(midBytes)),
                              ),
                              Positioned(
                                right: 6,
                                top: h * baseFrac - 6,
                                child: tick('0'),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) =>
                                _scrubAt(details.localPosition, constraints.maxWidth),
                            onHorizontalDragStart: (details) =>
                                _scrubAt(details.localPosition, constraints.maxWidth),
                            onHorizontalDragUpdate: (details) =>
                                _scrubAt(details.localPosition, constraints.maxWidth),
                            child: CustomPaint(
                              painter: _style == _PulseChartStyle.columns
                                  ? _PulseBarChartPainter(
                                      rxValues: rxValues,
                                      txValues: txValues,
                                      highlightIndex: peakIndex,
                                      scrubIndex: _scrubIndex,
                                    )
                                  : _PulseChartPainter(
                                      rxValues: rxValues,
                                      txValues: txValues,
                                      highlightIndex: peakIndex,
                                      scrubIndex: _scrubIndex,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (points.isNotEmpty)
            SizedBox(
              height: 18,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ticks = VpnStatsChartAxis.ticks(
                    points: points,
                    period: _chartPeriod,
                  );
                  const labelWidth = 44.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final tick in ticks)
                        Positioned(
                          left: VpnStatsChartAxis.tickLeft(
                            index: tick.index,
                            count: points.length,
                            width: constraints.maxWidth,
                            labelWidth: labelWidth,
                          ),
                          width: labelWidth,
                          child: Text(
                            tick.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CyberShieldTheme.labelCode(
                              color: tick.index == activeIndex
                                  ? CyberShieldColors.secondaryContainer
                                  : CyberShieldColors.onSurfaceVariant,
                              weight: tick.index == activeIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ).copyWith(fontSize: 10),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (scrub != null)
            _ScrubDetail(
              title: VpnStatsChartAxis.detailTitle(
                point: scrub,
                period: _chartPeriod,
              ),
              rxBytes: scrub.rxBytes,
              txBytes: scrub.txBytes,
              onClear: () => setState(() => _scrubIndex = null),
            )
          else
            Text(
              total > 0
                  ? 'Total ${VpnStatsFormat.bytes(total)} in selected window · drag chart for detail'
                  : 'No tunnel traffic in this window yet',
              style: CyberShieldTheme.bodySm(),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  static int _peakIndex(List<UsagePoint> points) {
    if (points.isEmpty) return -1;
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].totalBytes > points[best].totalBytes) {
        best = i;
      }
    }
    return best;
  }
}

class _PulseStyleToggle extends StatelessWidget {
  const _PulseStyleToggle({
    required this.style,
    required this.onChanged,
  });

  final _PulseChartStyle style;
  final ValueChanged<_PulseChartStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn({
      required _PulseChartStyle value,
      required IconData icon,
      required String tooltip,
    }) {
      final selected = style == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 34,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? CyberShieldColors.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected
                  ? Colors.white
                  : CyberShieldColors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            value: _PulseChartStyle.lines,
            icon: Icons.show_chart,
            tooltip: 'Line chart',
          ),
          btn(
            value: _PulseChartStyle.columns,
            icon: Icons.bar_chart,
            tooltip: 'Column chart',
          ),
        ],
      ),
    );
  }
}

class _ScrubDetail extends StatelessWidget {
  const _ScrubDetail({
    required this.title,
    required this.rxBytes,
    required this.txBytes,
    required this.onClear,
  });

  final String title;
  final int rxBytes;
  final int txBytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final total = rxBytes + txBytes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CyberShieldColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: CyberShieldTheme.labelCode(
                    color: CyberShieldColors.secondaryContainer,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '↓ ${VpnStatsFormat.bytes(rxBytes)}',
                      style: CyberShieldTheme.labelCode(
                        color: CyberShieldColors.secondaryContainer,
                      ),
                    ),
                    Text(
                      '↑ ${VpnStatsFormat.bytes(txBytes)}',
                      style: CyberShieldTheme.labelCode(
                        color: CyberShieldColors.primary,
                      ),
                    ),
                    Text(
                      'Σ ${VpnStatsFormat.bytes(total)}',
                      style: CyberShieldTheme.labelCode(
                        color: CyberShieldColors.onSurface,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Clear selection',
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            color: CyberShieldColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _PulseBarChartPainter extends CustomPainter {
  _PulseBarChartPainter({
    required this.rxValues,
    required this.txValues,
    required this.highlightIndex,
    this.scrubIndex,
  });

  final List<double> rxValues;
  final List<double> txValues;
  final int highlightIndex;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const topFrac = 0.08;
    const midFrac = 0.48;
    const baseFrac = 0.88;
    final grid = Paint()
      ..color = CyberShieldColors.surfaceVariant
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final y in [
      size.height * topFrac,
      size.height * midFrac,
      size.height * baseFrac,
    ]) {
      _dashLine(canvas, Offset(0, y), Offset(size.width, y), grid);
    }

    final n = math.min(rxValues.length, txValues.length);
    if (n == 0) {
      return;
    }

    var maxValue = 0.0;
    for (var i = 0; i < n; i++) {
      maxValue = math.max(maxValue, rxValues[i]);
      maxValue = math.max(maxValue, txValues[i]);
    }
    final scale = maxValue <= 0 ? 1.0 : maxValue;
    final span = baseFrac - topFrac;
    final slot = size.width / n;
    // Pair of Down/Up bars with a small gap, centered in each bucket.
    final pairGap = math.max(1.0, slot * 0.06);
    final barWidth = math.max(1.5, (slot * 0.72 - pairGap) / 2);
    final pairWidth = barWidth * 2 + pairGap;
    final baseY = size.height * baseFrac;
    final markIndex = scrubIndex ?? highlightIndex;

    for (var i = 0; i < n; i++) {
      final rx = rxValues[i].clamp(0.0, double.infinity);
      final tx = txValues[i].clamp(0.0, double.infinity);
      final centerX = (i + 0.5) * slot;
      final pairLeft = centerX - pairWidth / 2;
      final rxH = size.height * span * (rx / scale);
      final txH = size.height * span * (tx / scale);
      final selected = i == markIndex;
      final scrubbed = i == scrubIndex;

      final rxRect = Rect.fromLTWH(
        pairLeft,
        baseY - rxH,
        barWidth,
        math.max(rxH, 0),
      );
      final txRect = Rect.fromLTWH(
        pairLeft + barWidth + pairGap,
        baseY - txH,
        barWidth,
        math.max(txH, 0),
      );

      void drawBar(Rect rect, Color color, double alpha) {
        if (rect.height < 0.5) {
          canvas.drawLine(
            Offset(rect.center.dx, baseY),
            Offset(rect.center.dx, baseY - 2),
            Paint()
              ..color = color.withValues(alpha: 0.45)
              ..strokeWidth = 1.25,
          );
          return;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color = color.withValues(alpha: alpha)
            ..isAntiAlias = true,
        );
      }

      drawBar(
        rxRect,
        CyberShieldColors.secondaryContainer,
        selected ? 0.95 : 0.78,
      );
      drawBar(
        txRect,
        CyberShieldColors.primary,
        selected ? 0.95 : 0.72,
      );

      if (scrubbed) {
        final outline = Paint()
          ..color = CyberShieldColors.onSurface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..isAntiAlias = true;
        if (rxRect.height >= 0.5) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rxRect, const Radius.circular(2)),
            outline,
          );
        }
        if (txRect.height >= 0.5) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(txRect, const Radius.circular(2)),
            outline,
          );
        }
      }
    }
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total <= 0) {
      return;
    }
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _PulseBarChartPainter oldDelegate) =>
      oldDelegate.highlightIndex != highlightIndex ||
      oldDelegate.scrubIndex != scrubIndex ||
      !_PulseChartPainter._listEquals(oldDelegate.rxValues, rxValues) ||
      !_PulseChartPainter._listEquals(oldDelegate.txValues, txValues);
}

class _PulseChartPainter extends CustomPainter {
  _PulseChartPainter({
    required this.rxValues,
    required this.txValues,
    required this.highlightIndex,
    this.scrubIndex,
  });

  final List<double> rxValues;
  final List<double> txValues;
  final int highlightIndex;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    // Align with left Y labels: top / mid / baseline.
    const topFrac = 0.08;
    const midFrac = 0.48;
    const baseFrac = 0.88;
    final grid = Paint()
      ..color = CyberShieldColors.surfaceVariant
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final y in [
      size.height * topFrac,
      size.height * midFrac,
      size.height * baseFrac,
    ]) {
      _dashLine(canvas, Offset(0, y), Offset(size.width, y), grid);
    }

    if (rxValues.isEmpty || txValues.isEmpty) {
      final idle = Paint()
        ..color = CyberShieldColors.outlineVariant
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      _dashLine(
        canvas,
        Offset(0, size.height * baseFrac),
        Offset(size.width, size.height * baseFrac),
        idle,
      );
      return;
    }

    var maxValue = 0.0;
    for (final v in rxValues) {
      maxValue = math.max(maxValue, v);
    }
    for (final v in txValues) {
      maxValue = math.max(maxValue, v);
    }
    // All-zero windows still draw flat baseline lines (never blank / retry).
    final scale = maxValue <= 0 ? 1.0 : maxValue;
    final downPoints = _seriesPoints(
      size,
      rxValues,
      scale,
      topFrac: topFrac,
      baseFrac: baseFrac,
    );
    final upPoints = _seriesPoints(
      size,
      txValues,
      scale,
      topFrac: topFrac,
      baseFrac: baseFrac,
    );

    _fillCurve(canvas, size, upPoints, CyberShieldColors.primary, 0.10);
    _strokeCurve(canvas, upPoints, CyberShieldColors.primary, 1.75);
    _fillCurve(canvas, size, downPoints, CyberShieldColors.secondaryContainer, 0.12);
    _strokeCurve(canvas, downPoints, CyberShieldColors.secondaryContainer, 2.0);

    final markIndex = scrubIndex ?? highlightIndex;
    if (markIndex >= 0 && markIndex < downPoints.length) {
      if (scrubIndex != null) {
        final x = downPoints[markIndex].dx;
        canvas.drawLine(
          Offset(x, size.height * topFrac),
          Offset(x, size.height * baseFrac),
          Paint()
            ..color = CyberShieldColors.onSurfaceVariant.withValues(alpha: 0.55)
            ..strokeWidth = 1.25
            ..isAntiAlias = true,
        );
        _drawMark(canvas, upPoints[markIndex], CyberShieldColors.primary);
        _drawMark(
          canvas,
          downPoints[markIndex],
          CyberShieldColors.secondaryContainer,
        );
      } else {
        _drawMark(
          canvas,
          downPoints[markIndex],
          CyberShieldColors.secondaryContainer,
        );
      }
    }
  }

  void _drawMark(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(
      point,
      3.5,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      point,
      3.5,
      Paint()
        ..color = CyberShieldColors.surfaceContainerLowest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true,
    );
  }

  List<Offset> _seriesPoints(
    Size size,
    List<double> values,
    double maxValue, {
    required double topFrac,
    required double baseFrac,
  }) {
    final points = <Offset>[];
    final n = values.length;
    final span = baseFrac - topFrac;
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1);
      final norm = (values[i] / maxValue).clamp(0.0, 1.0);
      final y = size.height * (baseFrac - span * norm);
      points.add(Offset(size.width * t, y));
    }
    return points;
  }

  void _fillCurve(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Color color,
    double opacity,
  ) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path
      ..lineTo(points.last.dx, points.last.dy)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  void _strokeCurve(Canvas canvas, List<Offset> points, Color color, double width) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _PulseChartPainter oldDelegate) =>
      oldDelegate.highlightIndex != highlightIndex ||
      oldDelegate.scrubIndex != scrubIndex ||
      !_listEquals(oldDelegate.rxValues, rxValues) ||
      !_listEquals(oldDelegate.txValues, txValues);

  static bool _listEquals(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _SessionLedger extends StatelessWidget {
  const _SessionLedger({required this.state});

  final VpnConnectState state;

  @override
  Widget build(BuildContext context) {
    final peer = state.peer;
    final livePeer = state.isConnected ? peer : null;
    final sessionBytes = (state.rxBytes ?? 0) + (state.txBytes ?? 0);

    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 18, color: CyberShieldColors.onSurface),
            const SizedBox(width: 6),
            Text('Session Ledger', style: CyberShieldTheme.headlineSm()),
            const Spacer(),
            Text(
              livePeer != null ? 'Live' : 'No active session',
              style: CyberShieldTheme.labelBadge(
                color: CyberShieldColors.secondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (livePeer != null)
          _SessionRow(
            title: livePeer.server.name,
            subtitle:
                '${livePeer.server.countryCode ?? '—'} • WireGuard • ${_ip(livePeer)}',
            bytesLabel: VpnStatsFormat.bytes(sessionBytes),
            durationLabel: VpnStatsFormat.duration(state.sessionSeconds),
            active: true,
            flagCode: livePeer.server.countryCode,
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CyberShieldColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Connect to start an encrypted session. Totals above include committed history.',
              style: CyberShieldTheme.bodySm(),
            ),
          ),
        if (livePeer == null && state.overallTotals.activeSeconds > 0) ...[
          const SizedBox(height: 8),
          _SessionRow(
            title: 'Previous shielded time',
            subtitle: 'Committed totals',
            bytesLabel: VpnStatsFormat.bytes(
              state.overallTotals.rxBytes + state.overallTotals.txBytes,
            ),
            durationLabel:
                VpnStatsFormat.duration(state.overallTotals.activeSeconds),
            active: false,
          ),
        ],
      ],
    );
  }

  static String _ip(VpnPeerConfig peer) {
    if (peer.transport.serverIps.isNotEmpty) {
      return peer.transport.serverIps.first;
    }
    if (peer.interfaceAddresses.isNotEmpty) {
      return peer.interfaceAddresses.first.split('/').first;
    }
    return '—';
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.title,
    required this.subtitle,
    required this.bytesLabel,
    required this.durationLabel,
    required this.active,
    this.flagCode,
  });

  final String title;
  final String subtitle;
  final String bytesLabel;
  final String durationLabel;
  final bool active;
  final String? flagCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CyberShieldColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CyberShieldColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: flagCode != null
                ? Text(countryFlagEmoji(flagCode), style: const TextStyle(fontSize: 20))
                : Icon(
                    Icons.public,
                    size: 20,
                    color: active
                        ? CyberShieldColors.secondaryContainer
                        : CyberShieldColors.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: CyberShieldTheme.bodySm(
                          color: CyberShieldColors.onSurface,
                        ).copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CyberShieldColors.tertiary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: CyberShieldTheme.labelBadge(
                            color: CyberShieldColors.tertiary,
                          ).copyWith(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(subtitle, style: CyberShieldTheme.bodySm()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                bytesLabel,
                style: CyberShieldTheme.labelCode(
                  color: CyberShieldColors.onSurface,
                  weight: FontWeight.w700,
                ),
              ),
              Text(durationLabel, style: CyberShieldTheme.bodySm()),
            ],
          ),
        ],
      ),
    );
  }
}
