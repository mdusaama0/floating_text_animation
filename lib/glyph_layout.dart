import 'package:flutter/material.dart';

import 'models.dart';

/// Measures where each visible character of [task] sits on screen, using
/// the exact style the Text widget resolved, so letters start (and return)
/// pixel-aligned with the real text.
GlyphLayout? layoutGlyphs({
  required Task task,
  required GlobalKey stackKey,
  required TextStyle baseStyle,
  required double fontSize,
}) {
  final textCtx = task.textKey.currentContext;
  final stackCtx = stackKey.currentContext;
  if (textCtx == null || stackCtx == null) return null;

  final textBox = textCtx.findRenderObject() as RenderBox?;
  final stackBox = stackCtx.findRenderObject() as RenderBox?;
  if (textBox == null || stackBox == null || !textBox.hasSize) return null;

  final style = DefaultTextStyle.of(
    textCtx,
  ).style.merge(baseStyle).copyWith(decoration: TextDecoration.none);
  final scaler = MediaQuery.textScalerOf(textCtx);
  final direction = Directionality.of(textCtx);
  final origin = textBox.localToGlobal(Offset.zero, ancestor: stackBox);

  final tp = TextPainter(
    text: TextSpan(text: task.title, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout(maxWidth: textBox.size.width);

  final glyphs = <Glyph>[];
  var offset = 0;
  for (final ch in task.title.characters) {
    final start = offset;
    offset += ch.length;
    if (ch.trim().isEmpty) continue; // spaces don't fall
    final boxes = tp.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: offset),
    );
    if (boxes.isEmpty) continue;
    glyphs.add(Glyph(start, ch, boxes.first.toRect().shift(origin)));
  }
  tp.dispose();

  return GlyphLayout(
    glyphs: glyphs,
    style: style,
    scaler: scaler,
    direction: direction,
  );
}

/// Approximate visible bounds of a single character inside its text box.
/// A character's text box is a full line tall, but an "e" only fills the
/// x-height and a "g" hangs below the baseline, so colliding on the box
/// leaves letters floating and overlapping. This keeps the collision
/// circle on the ink itself.
Rect inkRect(String ch, TextPainter p, double fontSize) {
  final baseline = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final capH = fontSize * 0.71;
  final xH = fontSize * 0.52;
  final desc = fontSize * 0.22;

  final isUpper = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
  final isDigit = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  double top, bottom;
  if (isUpper || isDigit || 'bdfhiklt'.contains(ch)) {
    top = baseline - capH;
    bottom = baseline;
  } else if ('gpqy'.contains(ch)) {
    top = baseline - xH;
    bottom = baseline + desc;
  } else if (ch == 'j') {
    top = baseline - capH;
    bottom = baseline + desc;
  } else if (ch == "'" || ch == '"' || ch == '`') {
    top = baseline - capH;
    bottom = baseline - capH * 0.6;
  } else if ('.,'.contains(ch)) {
    top = baseline - fontSize * 0.15;
    bottom = baseline;
  } else {
    top = baseline - xH;
    bottom = baseline;
  }
  return Rect.fromLTRB(0, top, p.width, bottom);
}
