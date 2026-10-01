import 'package:flutter/material.dart';

enum TaskState { active, done, restoring }

class Task {
  Task(this.title);
  final String title;
  final GlobalKey textKey = GlobalKey();
  TaskState state = TaskState.active;
}

class Glyph {
  const Glyph(this.offset, this.char, this.rect);
  final int offset; // code-unit offset of this character in the title
  final String char;
  final Rect rect; // in stack coordinates
}

class Letter {
  Letter({
    required this.task,
    required this.offset,
    required this.painter,
    required this.radius,
    required this.anchor,
    required this.pos,
  });

  final int task;
  final int offset;
  final TextPainter painter;
  final double radius; // collision radius, sized to the visible glyph
  final Offset anchor; // centre of the visible glyph inside its text box

  Offset pos; // position of the visible glyph's centre
  Offset vel = Offset.zero;
  double angle = 0;
  double spin = 0; // rad/s; heavily damped, so letters turn a bit and stop
  bool touching = false;

  bool restoring = false;
  double restoreClock = 0; // 0 → 1 over restoreDuration
  double restoreDelay = 0; // stagger, as a fraction of restoreDuration
  Tween<Offset>? restorePos;
  Tween<double>? restoreAngle;
}

class GlyphLayout {
  const GlyphLayout({
    required this.glyphs,
    required this.style,
    required this.scaler,
    required this.direction,
  });

  final List<Glyph> glyphs;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
}
