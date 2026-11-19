import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/cyber_shield_colors.dart';
import '../../../../core/theme/cyber_shield_theme.dart';
import '../vpn_connect_cubit.dart';
import '../vpn_privacy_disclosure_sheet.dart';

enum ConnectDialVisual { disconnected, connecting, connected }

class ConnectDial extends StatefulWidget {
  const ConnectDial({super.key, required this.connect, required this.visual});

  final VpnConnectState connect;
  final ConnectDialVisual visual;

  @override
  State<ConnectDial> createState() => _ConnectDialState();
}

class _ConnectDialState extends State<ConnectDial> with SingleTickerProviderStateMixin {
  late final AnimationController _iconSpin;

  @override
  void initState() {
    super.initState();
    _iconSpin = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant ConnectDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visual != widget.visual) {
      _syncSpin();
    }
  }

  void _syncSpin() {
    if (widget.visual == ConnectDialVisual.connecting) {
      _iconSpin.repeat();
    } else {
      _iconSpin.stop();
      _iconSpin.value = 0;
    }
  }

  @override
  void dispose() {
    _iconSpin.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final cubit = context.read<VpnConnectCubit>();
    final connect = widget.connect;
    if (connect.canDisconnect) {
      await cubit.disconnect();
    } else if (connect.canConnect) {
      final allowed = await ensureVpnPrivacyDisclosureAccepted(context);
      if (!allowed || !mounted) {
        return;
      }
      await cubit.connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = widget.visual;
    final (icon, label, iconColor, glow) = switch (visual) {
      ConnectDialVisual.connected => (Icons.verified_user, 'SECURE', CyberShieldColors.secondary, true),
      ConnectDialVisual.connecting => (Icons.sync, 'HANDSHAKING', CyberShieldColors.secondaryContainer, true),
      ConnectDialVisual.disconnected => (Icons.power_settings_new, 'TAP TO CONNECT', CyberShieldColors.outline, false),
    };

    return SizedBox(
      height: 200,
      child: Center(
        child: GestureDetector(
          onTap: widget.connect.isBusy && !widget.connect.canDisconnect ? null : _onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 180,
            height: 180,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CyberShieldColors.surfaceContainerHigh,
              border: Border.all(
                color: glow
                    ? CyberShieldColors.secondaryContainer.withValues(alpha: 0.5)
                    : CyberShieldColors.outlineVariant.withValues(alpha: 0.4),
              ),
              boxShadow: glow
                  ? [BoxShadow(color: CyberShieldColors.secondaryContainer.withValues(alpha: 0.35), blurRadius: 38)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18)],
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    CyberShieldColors.primaryContainer,
                    CyberShieldColors.surfaceContainerHighest,
                    Color(0xCC00F4FE),
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (visual != ConnectDialVisual.connected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CyberShieldColors.surfaceContainerHighest.withValues(
                            alpha: visual == ConnectDialVisual.connecting ? 0.35 : 0.55,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 7,
                    left: 22,
                    right: 22,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: visual == ConnectDialVisual.connected ? 0.3 : 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RotationTransition(
                        turns: visual == ConnectDialVisual.connecting ? _iconSpin : const AlwaysStoppedAnimation(0),
                        child: Icon(icon, size: 52, color: iconColor),
                      ),
                      const SizedBox(height: 5),
                      Text(label, style: CyberShieldTheme.labelBadge(color: iconColor)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
