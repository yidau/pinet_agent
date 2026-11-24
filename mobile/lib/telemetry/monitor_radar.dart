import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';

enum RadarState { capturing, degraded, connecting, stale, offline, locked }

class MonitorRadar extends StatefulWidget {
  const MonitorRadar({super.key, required this.state, required this.revision});

  final RadarState state;
  final int revision;

  @override
  State<MonitorRadar> createState() => _MonitorRadarState();
}

class _MonitorRadarState extends State<MonitorRadar>
    with TickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  late final _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _animate = false;

  bool get _isLive =>
      widget.state == RadarState.capturing ||
      widget.state == RadarState.degraded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (_animate != allowed) {
      _animate = allowed;
      _update(replay: true);
    }
  }

  @override
  void didUpdateWidget(MonitorRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state ||
        widget.revision != oldWidget.revision) {
      _update(replay: widget.revision != oldWidget.revision);
    }
  }

  void _update({required bool replay}) {
    if (!_animate || !_isLive) _pulse.stop();
    if (_animate && _isLive && replay) _pulse.forward(from: 0);
    if (_animate &&
        (widget.state == RadarState.connecting ||
            widget.state == RadarState.offline)) {
      if (!_ambient.isAnimating) {
        _ambient.repeat(reverse: widget.state == RadarState.offline);
      }
    } else {
      _ambient.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    final color = switch (widget.state) {
      RadarState.capturing => theme.primary,
      RadarState.degraded => ConsoleColors.warningOf(context),
      _ => theme.onSurfaceVariant,
    };
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: 116,
        child: CustomPaint(
          painter: _RadarPainter(widget.state, color, _pulse, _ambient),
          child: Center(
            child: Icon(
              widget.state == RadarState.locked
                  ? Icons.lock_outline
                  : Icons.sensors,
              size: 23,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ambient.dispose();
    super.dispose();
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.state, this.color, this.pulse, this.ambient)
    : super(repaint: Listenable.merge([pulse, ambient]));
  final RadarState state;
  final Color color;
  final Animation<double> pulse;
  final Animation<double> ambient;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final ring = Rect.fromCircle(center: center, radius: radius);
    final lines = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final scale in [0.33, 0.63, 0.95]) {
      canvas.drawCircle(center, radius * scale, lines);
    }
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      lines,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      lines,
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    switch (state) {
      case RadarState.capturing:
        canvas.drawArc(
          ring,
          pulse.value * math.pi * 2 - math.pi / 2,
          math.pi / 2,
          false,
          arc..color = color.withValues(alpha: 1 - 0.65 * pulse.value),
        );
      case RadarState.connecting:
        canvas.drawArc(ring, ambient.value * math.pi * 2, 0.45, false, arc);
      default:
        final opacity = state == RadarState.offline
            ? 0.35 + ambient.value * 0.35
            : state == RadarState.degraded
            ? 1 - pulse.value * 0.5
            : 0.6;
        for (var segment = 0; segment < 8; segment++) {
          canvas.drawArc(
            ring,
            segment * math.pi / 4,
            0.38,
            false,
            arc..color = color.withValues(alpha: opacity),
          );
        }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.color != color;
}
