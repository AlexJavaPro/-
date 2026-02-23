import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PatternInput extends StatefulWidget {
  const PatternInput({
    super.key,
    required this.onPatternCompleted,
    this.enabled = true,
    this.size = 280,
    this.activeColor = const Color(0xFF2165F5),
    this.idleColor = const Color(0xFF9EC5FF),
  });

  final ValueChanged<List<int>> onPatternCompleted;
  final bool enabled;
  final double size;
  final Color activeColor;
  final Color idleColor;

  @override
  State<PatternInput> createState() => _PatternInputState();
}

class _PatternInputState extends State<PatternInput> {
  final List<int> _selected = <int>[];
  Offset? _fingerPosition;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final centers = _resolveCenters(side);
          final hitRadius = side / 7.2;

          return Center(
            child: SizedBox.square(
              dimension: side,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.enabled
                    ? (details) => _handleDrag(details.localPosition, centers, hitRadius)
                    : null,
                onPanUpdate: widget.enabled
                    ? (details) => _handleDrag(details.localPosition, centers, hitRadius)
                    : null,
                onPanEnd: widget.enabled ? (_) => _completePattern() : null,
                onPanCancel: widget.enabled ? _clearPattern : null,
                child: CustomPaint(
                  painter: _PatternPainter(
                    centers: centers,
                    selected: List<int>.of(_selected, growable: false),
                    fingerPosition: _fingerPosition,
                    activeColor: widget.activeColor,
                    idleColor: widget.idleColor,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Offset> _resolveCenters(double side) {
    final cell = side / 3;
    final points = <Offset>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        points.add(Offset(col * cell + cell / 2, row * cell + cell / 2));
      }
    }
    return points;
  }

  void _handleDrag(Offset position, List<Offset> centers, double hitRadius) {
    _fingerPosition = position;

    for (var index = 0; index < centers.length; index++) {
      final distance = (centers[index] - position).distance;
      if (distance <= hitRadius) {
        if (!_selected.contains(index)) {
          setState(() {
            _selected.add(index);
          });
        } else {
          setState(() {});
        }
        return;
      }
    }
    setState(() {});
  }

  void _completePattern() {
    final pattern = List<int>.of(_selected);
    _fingerPosition = null;
    setState(() {});

    if (pattern.length >= 4) {
      widget.onPatternCompleted(pattern);
    }

    Future<void>.delayed(const Duration(milliseconds: 180), _clearPattern);
  }

  void _clearPattern() {
    if (!mounted) {
      return;
    }
    setState(() {
      _selected.clear();
      _fingerPosition = null;
    });
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.centers,
    required this.selected,
    required this.fingerPosition,
    required this.activeColor,
    required this.idleColor,
  });

  final List<Offset> centers;
  final List<int> selected;
  final Offset? fingerPosition;
  final Color activeColor;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeRadius = size.width / 10.5;

    final activeLinePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (selected.length > 1) {
      final path = Path()..moveTo(centers[selected.first].dx, centers[selected.first].dy);
      for (var i = 1; i < selected.length; i++) {
        final point = centers[selected[i]];
        path.lineTo(point.dx, point.dy);
      }
      if (fingerPosition != null) {
        path.lineTo(fingerPosition!.dx, fingerPosition!.dy);
      }
      canvas.drawPath(path, activeLinePaint);
    }

    for (var i = 0; i < centers.length; i++) {
      final center = centers[i];
      final isActive = selected.contains(i);
      final fillPaint = Paint()
        ..color = isActive
            ? activeColor.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.86)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = isActive ? activeColor : idleColor
        ..strokeWidth = isActive ? 3.5 : 2.2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, nodeRadius, fillPaint);
      canvas.drawCircle(center, nodeRadius, strokePaint);

      if (isActive) {
        canvas.drawCircle(
          center,
          nodeRadius / 3.2,
          Paint()..color = activeColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return !listEquals(oldDelegate.selected, selected) ||
        oldDelegate.fingerPosition != fingerPosition ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.idleColor != idleColor;
  }
}
