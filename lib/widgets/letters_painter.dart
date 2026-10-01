import 'package:flutter/material.dart';

import '../models.dart';

/// Draws every loose letter, rotated about its centre.
/// Repaints via the frame notifier, so the widget tree never rebuilds per frame.
class LettersPainter extends CustomPainter {
  LettersPainter(this.letters, Listenable repaint) : super(repaint: repaint);

  final List<Letter> letters;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in letters) {
      canvas
        ..save()
        ..translate(l.pos.dx, l.pos.dy)
        ..rotate(l.angle);
      // Rotate about the visible glyph's centre, not its line box.
      l.painter.paint(canvas, -l.anchor);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(LettersPainter oldDelegate) =>
      oldDelegate.letters != letters;
}
