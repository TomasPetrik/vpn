import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/cyber_shield_colors.dart';
import '../../../core/theme/cyber_shield_theme.dart';
import '../../device/domain/vpn_peer_config.dart';
import 'home/country_flag.dart';
import 'vpn_connect_cubit.dart';
import 'vpn_stats_format.dart';

enum _StatsPeriod { today, days7, days30, all }

class VpnStatsPage extends StatefulWidget {
  const VpnStatsPage({super.key});

  @override
  State<VpnStatsPage> createState() => _VpnStatsPageState();
}

class _VpnStatsPageState extends State<VpnStatsPage> {
  _StatsPeriod _period = _StatsPeriod.days7;

  @override
  void initState() {
    super.initState();
    context.read<VpnConnectCubit>().refreshCommittedTotals();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberShieldColors.background,
      body: SafeArea(
        child: BlocBuilder<VpnConnectCubit, VpnConnectState>(
          builder: (context, state) {
            final overall = state.overallTotals;
            final totalBytes = overall.rxBytes + overall.txBytes;
            final rxShare =
                totalBytes == 0 ? 0.0 : overall.rxBytes / totalBytes;
            final txShare =
                totalBytes == 0 ? 0.0 : overall.txBytes / totalBytes;
            final days = switch (_period) {
              _StatsPeriod.today => 1,
              _StatsPeriod.days7 => 7,
              _StatsPeriod.days30 => 30,
              _StatsPeriod.all => math.max(1, overall.activeSeconds ~/ 86400),
            };
            final avgRxPerDay = overall.rxBytes / days;
            final avgTxPerDay = overall.txBytes / days;

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
                                onPressed: () => context
                                    .read<VpnConnectCubit>()
                                    .refreshCommittedTotals(),
                                icon: const Icon(Icons.refresh, size: 20),
                                color: CyberShieldColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _PeriodSelector(
                          period: _period,
                          onChanged: (value) =>
                              setState(() => _period = value),
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
                                        ? 'Live session included'
                                        : 'Committed usage',
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
                              bytes: overall.rxBytes,
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
                              bytes: overall.txBytes,
                              share: txShare,
                              avgPerDay: avgTxPerDay,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BandwidthPulseCard(
                        rxBytes: overall.rxBytes,
                        txBytes: overall.txBytes,
                        period: _period,
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
          tab(_StatsPeriod.today, 'Today'),
          tab(_StatsPeriod.days7, 'Last 7 Days'),
          tab(_StatsPeriod.days30, 'Last 30 Days'),
          tab(_StatsPeriod.all, 'All Time'),
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

class _BandwidthPulseCard extends StatelessWidget {
  const _BandwidthPulseCard({
    required this.rxBytes,
    required this.txBytes,
    required this.period,
  });

  final int rxBytes;
  final int txBytes;
  final _StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final labels = switch (period) {
      _StatsPeriod.today => const ['0h', '4h', '8h', '12h', '16h', '20h', 'Now'],
      _ => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    };

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
                      period == _StatsPeriod.today
                          ? 'Today Bandwidth Pulse'
                          : 'Daily Bandwidth Pulse',
                      style: CyberShieldTheme.headlineSm(),
                    ),
                    Text(
                      'Data encrypted end-to-end',
                      style: CyberShieldTheme.bodySm(),
                    ),
                  ],
                ),
              ),
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
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _PulseChartPainter(
                hasData: rxBytes + txBytes > 0,
                rxRatio: rxBytes == 0 && txBytes == 0
                    ? 0.5
                    : rxBytes / math.max(1, rxBytes + txBytes),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < labels.length; i++)
                Text(
                  labels[i],
                  style: CyberShieldTheme.labelCode(
                    color: i == 3
                        ? CyberShieldColors.secondaryContainer
                        : CyberShieldColors.onSurfaceVariant,
                    weight: i == 3 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (rxBytes + txBytes > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Total ${VpnStatsFormat.bytes(rxBytes + txBytes)} in selected window',
              style: CyberShieldTheme.bodySm(),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseChartPainter extends CustomPainter {
  _PulseChartPainter({required this.hasData, required this.rxRatio});

  final bool hasData;
  final double rxRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = CyberShieldColors.surfaceVariant
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke;
    for (final y in [size.height * 0.15, size.height * 0.45, size.height * 0.75]) {
      _dashLine(canvas, Offset(0, y), Offset(size.width, y), grid);
    }

    if (!hasData) {
      final idle = Paint()
        ..color = CyberShieldColors.outlineVariant
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final y = size.height * 0.85;
      _dashLine(canvas, Offset(0, y), Offset(size.width, y), idle);
      return;
    }

    final downPoints = _curve(size, amplitude: 0.55 + rxRatio * 0.25, phase: 0);
    final upPoints = _curve(size, amplitude: 0.25 + (1 - rxRatio) * 0.2, phase: 0.35);

    _fillCurve(canvas, size, upPoints, CyberShieldColors.primary, 0.15);
    _strokeCurve(canvas, upPoints, CyberShieldColors.primary, 1.75);
    _fillCurve(canvas, size, downPoints, CyberShieldColors.secondaryContainer, 0.35);
    _strokeCurve(canvas, downPoints, CyberShieldColors.secondaryContainer, 2.25);

    final peak = downPoints[downPoints.length ~/ 2];
    canvas.drawCircle(
      peak,
      4.5,
      Paint()..color = CyberShieldColors.secondaryContainer,
    );
    canvas.drawCircle(
      peak,
      4.5,
      Paint()
        ..color = CyberShieldColors.surfaceContainerLowest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  List<Offset> _curve(Size size, {required double amplitude, required double phase}) {
    final points = <Offset>[];
    const steps = 6;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final wave = math.sin((t + phase) * math.pi * 1.6);
      final y = size.height * (0.82 - amplitude * (0.45 + 0.55 * ((wave + 1) / 2)));
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
        ..maskFilter = color == CyberShieldColors.secondaryContainer
            ? const MaskFilter.blur(BlurStyle.normal, 1.5)
            : null,
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
      oldDelegate.hasData != hasData || oldDelegate.rxRatio != rxRatio;
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
