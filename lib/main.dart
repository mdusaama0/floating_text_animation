// Floating Text — Flutter
//
// Tap a task and its letters break free, tumble, and pile up.
// Tilt the phone to slosh them around (lay it flat and they float).
// Tap the task again, or the reset button, to fly the letters home.
//
// Setup:
//   flutter create floating_text && cd floating_text
//   flutter pub add sensors_plus
//   replace lib/main.dart with this file
//
// Requires Flutter 3.27+ (uses Color.withValues) and Dart 3.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() => runApp(const FloatingTextApp());

class FloatingTextApp extends StatelessWidget {
  const FloatingTextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const FloatingTextTasks(
        title: 'September 29',
        tasks: [
          'Review project brief',
          'Check the mailbox',
          'Finish reading notes',
          'Call design partner',
          'Send weekly update',
          'Water the plants',
          'Book dentist appointment',
          'Plan weekend groceries',
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget (parameters mirror the original's inspector controls)
// ---------------------------------------------------------------------------

class FloatingTextTasks extends StatefulWidget {
  const FloatingTextTasks({
    super.key,
    required this.title,
    required this.tasks,
    this.fontSize = 17,
    this.completedOpacity = 0.3,
    this.gravityStrength = 15,
    this.scatterStrength = 4.5,
    this.restoreDuration = const Duration(milliseconds: 600),
  });

  final String title;
  final List<String> tasks;

  /// Task title size in logical pixels.
  final double fontSize;

  /// Opacity of the struck-through "ghost" left behind by a completed task.
  final double completedOpacity;

  /// Scales device tilt (or plain downward gravity when no sensor exists).
  final double gravityStrength;

  /// How hard letters burst apart when a task is completed.
  final double scatterStrength;

  /// How long letters take to fly back into place.
  final Duration restoreDuration;

  @override
  State<FloatingTextTasks> createState() => _FloatingTextTasksState();
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

enum _TaskState { active, done, restoring }

class _Task {
  _Task(this.title);
  final String title;
  final GlobalKey textKey = GlobalKey();
  _TaskState state = _TaskState.active;
}

class _Glyph {
  const _Glyph(this.offset, this.char, this.rect);
  final int offset; // code-unit offset of this character in the title
  final String char;
  final Rect rect; // in stack coordinates
}

class _Letter {
  _Letter({
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

  // Restore animation
  bool restoring = false;
  double restoreClock = 0; // 0 → 1 over restoreDuration
  double restoreDelay = 0; // stagger, as a fraction of restoreDuration
  Offset restoreFrom = Offset.zero;
  double angleFrom = 0;
  Offset home = Offset.zero;
}

// Physics tuning
const double _pxPerG = 100; // gravityStrength 15 → 1500 px/s² at 1g
const double _restitution = 0.25; // bounciness
const double _wallFriction = 0.92; // tangential damping on wall contact
const double _airDrag = 0.35; // per second
const double _impactThreshold = 40; // px/s; softer contacts don't bounce
const double _spinDrag = 4; // per second: a tossed letter turns, then stops
const double _contactSpinDamp = 0.85; // per substep while touching something
const double _impactKick = 0.008; // rad/s of spin per px/s of hard impact
const int _substeps = 3; // physics steps per frame
const int _solverIterations = 4; // contact passes per step; more = firmer pile
const double _letterGap = 1.5; // px of breathing room around each letter

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _FloatingTextTasksState extends State<FloatingTextTasks>
    with SingleTickerProviderStateMixin {
  late final List<_Task> _tasks = [for (final t in widget.tasks) _Task(t)];
  final List<_Letter> _letters = [];
  final GlobalKey _stackKey = GlobalKey();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final math.Random _rng = math.Random();

  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  Size _bounds = Size.zero;

  /// Height of the bottom safe area (home indicator / gesture bar). Letters
  /// land on top of it instead of piling up underneath.
  double _bottomInset = 0;

  /// Gravity direction in screen space, magnitude ≈ 1 when the phone is
  /// upright, ≈ 0 when it lies flat. Defaults to straight down, which is what
  /// you get on simulators, desktop and web.
  Offset _gravity = const Offset(0, 1);
  StreamSubscription<AccelerometerEvent>? _accelSub;

  TextStyle get _baseStyle => TextStyle(
    fontSize: widget.fontSize,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: 0,
    color: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _listenToMotion();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    _frame.dispose();
    for (final l in _letters) {
      l.painter.dispose();
    }
    super.dispose();
  }

  // ---- Device motion -------------------------------------------------------

  void _listenToMotion() {
    if (kIsWeb) return;
    try {
      _accelSub =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen(
            (e) {
              // sensors_plus reports the reaction to gravity in device axes
              // (x right, y up). Screen space has y pointing down, hence the
              // sign flips. If letters fall the wrong way on a device, flip here.
              final target = Offset(-e.x, e.y) / 9.81;
              _gravity = Offset.lerp(
                _gravity,
                target,
                0.25,
              )!; // low-pass filter
            },
            onError: (_) {}, // no sensor: keep default downward gravity
            cancelOnError: true,
          );
    } catch (_) {
      // Platform without sensor support.
    }
  }

  // ---- Interaction ---------------------------------------------------------

  void _toggle(int i) {
    switch (_tasks[i].state) {
      case _TaskState.active:
        _complete(i);
      case _TaskState.done:
        _restore(i);
      case _TaskState.restoring:
        break;
    }
  }

  void _resetAll() {
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].state == _TaskState.done) _restore(i);
    }
  }

  void _complete(int i) {
    final layout = _layoutGlyphs(i);
    if (layout == null) return;

    for (final g in layout.glyphs) {
      final painter = TextPainter(
        text: TextSpan(text: g.char, style: layout.style),
        textDirection: layout.direction,
        textScaler: layout.scaler,
      )..layout();

      final ink = _inkRect(
        g.char,
        painter,
        layout.scaler.scale(widget.fontSize),
      );
      final letter = _Letter(
        task: i,
        offset: g.offset,
        painter: painter,
        // Circle around the whole visible glyph plus a small gap, so
        // letters in the pile sit next to each other instead of overlapping.
        radius:
            math.max(3.0, 0.5 * math.max(ink.width, ink.height)) + _letterGap,
        anchor: ink.center,
        pos: g.rect.topLeft + ink.center,
      );

      // Burst mostly upward with a random spread, and a random toss of
      // rotation. Drag stops the turn after at most ~80°, so letters land
      // at scattered angles without ever spinning continuously.
      final dir = -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi * 1.1;
      final speed = widget.scatterStrength * (30 + _rng.nextDouble() * 70);
      letter.vel = Offset(math.cos(dir), math.sin(dir)) * speed;
      letter.spin =
          (_rng.nextDouble() * 2 - 1) * (1.5 + widget.scatterStrength * 0.9);

      _letters.add(letter);
    }

    setState(() => _tasks[i].state = _TaskState.done);
    _startTicker();
  }

  void _restore(int i) {
    final layout = _layoutGlyphs(i);
    final homes = {
      for (final g in layout?.glyphs ?? const <_Glyph>[])
        g.offset: g.rect.topLeft,
    };

    final mine = _letters.where((l) => l.task == i).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (mine.isEmpty) {
      setState(() => _tasks[i].state = _TaskState.active);
      return;
    }

    for (var k = 0; k < mine.length; k++) {
      final l = mine[k];
      l
        ..restoring = true
        ..restoreClock = 0
        // Stagger left-to-right across the first 30% of the duration.
        ..restoreDelay = mine.length == 1 ? 0 : 0.3 * k / (mine.length - 1)
        ..restoreFrom = l.pos
        ..angleFrom = _wrapAngle(l.angle)
        ..home = homes[l.offset] == null ? l.pos : homes[l.offset]! + l.anchor
        ..vel = Offset.zero;
    }

    setState(() => _tasks[i].state = _TaskState.restoring);
    _startTicker();
  }

  /// Measures where each visible character of task [i] sits on screen, using
  /// the exact style the Text widget resolved, so letters start (and return)
  /// pixel-aligned with the real text.
  ({
    List<_Glyph> glyphs,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  })?
  _layoutGlyphs(int i) {
    final task = _tasks[i];
    final textCtx = task.textKey.currentContext;
    final stackCtx = _stackKey.currentContext;
    if (textCtx == null || stackCtx == null) return null;

    final textBox = textCtx.findRenderObject() as RenderBox?;
    final stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (textBox == null || stackBox == null || !textBox.hasSize) return null;

    final style = DefaultTextStyle.of(
      textCtx,
    ).style.merge(_baseStyle).copyWith(decoration: TextDecoration.none);
    final scaler = MediaQuery.textScalerOf(textCtx);
    final direction = Directionality.of(textCtx);
    final origin = textBox.localToGlobal(Offset.zero, ancestor: stackBox);

    final tp = TextPainter(
      text: TextSpan(text: task.title, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: textBox.size.width);

    final glyphs = <_Glyph>[];
    var offset = 0;
    for (final ch in task.title.characters) {
      final start = offset;
      offset += ch.length;
      if (ch.trim().isEmpty) continue; // spaces don't fall
      final boxes = tp.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: offset),
      );
      if (boxes.isEmpty) continue;
      glyphs.add(_Glyph(start, ch, boxes.first.toRect().shift(origin)));
    }
    tp.dispose();

    return (glyphs: glyphs, style: style, scaler: scaler, direction: direction);
  }

  // ---- Simulation ----------------------------------------------------------

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 30);
    _lastTick = elapsed;
    if (dt <= 0 || _bounds.isEmpty) return;

    final h = dt / _substeps;
    for (var s = 0; s < _substeps; s++) {
      _simulate(h);
    }
    _advanceRestores(dt);

    _frame.value++;
    if (_letters.isEmpty) _ticker.stop();
  }

  void _simulate(double h) {
    final g = _gravity * (widget.gravityStrength * _pxPerG);
    final bodies = [
      for (final l in _letters)
        if (!l.restoring) l,
    ];

    for (final l in bodies) {
      l.vel = (l.vel + g * h) * (1 - _airDrag * h);
      l.pos += l.vel * h;
      l.angle += l.spin * h;
      l.spin *= 1 - _spinDrag * h;
      l.touching = false;
    }

    // Several contact passes per step. With a single pass, the weight of a
    // deep pile squashed the bottom rows into each other; repeating the
    // separation lets every layer push back fully. Only the first pass
    // changes velocities (bounces, friction, knocks); the rest just
    // untangle positions.
    for (var it = 0; it < _solverIterations; it++) {
      final first = it == 0;
      _solveContacts(bodies, first);
      for (final l in bodies) {
        _collideWalls(l, first);
      }
    }

    for (final l in bodies) {
      // Anything resting on something stops turning almost at once.
      if (l.touching) l.spin *= _contactSpinDamp;
    }
  }

  /// Finds touching pairs with a uniform grid (each letter only checks its
  /// neighbouring cells) instead of testing every pair, so extra solver
  /// passes stay cheap even with a couple of hundred letters.
  void _solveContacts(List<_Letter> bodies, bool withVelocity) {
    if (bodies.length < 2) return;
    var maxR = 0.0;
    for (final l in bodies) {
      if (l.radius > maxR) maxR = l.radius;
    }
    final cell = maxR * 2;

    final grid = <int, List<_Letter>>{};
    int key(int cx, int cy) => (cy + 64) * 4096 + (cx + 64);
    for (final l in bodies) {
      final cx = (l.pos.dx / cell).floor();
      final cy = (l.pos.dy / cell).floor();
      (grid[key(cx, cy)] ??= []).add(l);
    }

    // Visit each cell against itself and 4 of its neighbours, so every
    // nearby pair is checked exactly once.
    const neighbours = [(1, 0), (-1, 1), (0, 1), (1, 1)];
    for (final entry in grid.entries) {
      final k = entry.key;
      final cx = k % 4096 - 64;
      final cy = k ~/ 4096 - 64;
      final here = entry.value;

      for (var a = 0; a < here.length; a++) {
        for (var b = a + 1; b < here.length; b++) {
          _collidePair(here[a], here[b], withVelocity);
        }
      }
      for (final (dx, dy) in neighbours) {
        final there = grid[key(cx + dx, cy + dy)];
        if (there == null) continue;
        for (final a in here) {
          for (final b in there) {
            _collidePair(a, b, withVelocity);
          }
        }
      }
    }
  }

  void _collidePair(_Letter a, _Letter b, bool withVelocity) {
    final d = b.pos - a.pos;
    final minD = a.radius + b.radius;
    final dist2 = d.distanceSquared;
    if (dist2 >= minD * minD) return;

    a.touching = true;
    b.touching = true;

    final dist = math.sqrt(dist2);
    final n = dist > 1e-4 ? d / dist : const Offset(0, 1);

    // Separate the overlap.
    final push = n * ((minD - dist) * 0.5);
    a.pos -= push;
    b.pos += push;
    if (!withVelocity) return;

    // Bounce along the normal. Gentle contacts (letters resting on each
    // other in a pile) are fully inelastic, so the pile doesn't buzz.
    final rel = b.vel - a.vel;
    final vn = rel.dx * n.dx + rel.dy * n.dy;
    if (vn >= 0) return;
    final hard = -vn > _impactThreshold;
    final e = hard ? _restitution : 0.0;
    final impulse = n * (-(1 + e) * vn * 0.5);
    a.vel -= impulse;
    b.vel += impulse;

    // A real knock nudges both letters to a new angle (one short turn,
    // quickly damped). Resting contact never does, so piles stay still.
    if (hard) {
      a.spin += _knock(-vn);
      b.spin += _knock(-vn);
    }
  }

  double _knock(double impact) =>
      (_rng.nextDouble() * 2 - 1) * math.min(impact, 400) * _impactKick;

  void _collideWalls(_Letter l, bool withVelocity) {
    final r = l.radius;
    var x = l.pos.dx, y = l.pos.dy, vx = l.vel.dx, vy = l.vel.dy;
    var impact = 0.0;
    // Later solver passes only fix positions; friction is applied once.
    final friction = withVelocity ? _wallFriction : 1.0;

    final floor = _bounds.height - _bottomInset;
    if (y > floor - r) {
      y = floor - r;
      if (vy > 0) {
        impact = math.max(impact, vy);
        vy = _bounce(vy);
      }
      vx *= friction;
      l.touching = true;
    }
    if (y < r) {
      y = r;
      if (vy < 0) {
        impact = math.max(impact, -vy);
        vy = _bounce(vy);
      }
      vx *= friction;
      l.touching = true;
    }
    if (x < r) {
      x = r;
      if (vx < 0) {
        impact = math.max(impact, -vx);
        vx = _bounce(vx);
      }
      vy *= friction;
      l.touching = true;
    }
    if (x > _bounds.width - r) {
      x = _bounds.width - r;
      if (vx > 0) {
        impact = math.max(impact, vx);
        vx = _bounce(vx);
      }
      vy *= friction;
      l.touching = true;
    }

    l.pos = Offset(x, y);
    l.vel = Offset(vx, vy);
    // Hitting the floor or a wall hard knocks the letter to a new angle.
    if (impact > _impactThreshold) l.spin += _knock(impact);
  }

  double _bounce(double v) {
    final out = -v * _restitution;
    return out.abs() < 25 ? 0 : out; // kill micro-bounces so piles settle
  }

  void _advanceRestores(double dt) {
    final secs = widget.restoreDuration.inMicroseconds / 1e6;
    final step = secs <= 0 ? 1.0 : dt / secs;
    var anyFinished = false;

    _letters.removeWhere((l) {
      if (!l.restoring) return false;
      l.restoreClock += step;
      final t = ((l.restoreClock - l.restoreDelay) / 0.7)
          .clamp(0.0, 1.0)
          .toDouble();
      final e = Curves.easeInOutCubic.transform(t);
      l.pos = Offset.lerp(l.restoreFrom, l.home, e)!;
      l.angle = l.angleFrom * (1 - e);
      if (l.restoreClock < 1) return false;
      l.painter.dispose();
      anyFinished = true;
      return true;
    });

    if (!anyFinished) return;
    final stillOut = {for (final l in _letters) l.task};
    setState(() {
      for (var i = 0; i < _tasks.length; i++) {
        if (_tasks[i].state == _TaskState.restoring && !stillOut.contains(i)) {
          _tasks[i].state = _TaskState.active;
        }
      }
    });
  }

  /// Approximate visible bounds of a single character inside its text box.
  /// A character's text box is a full line tall, but an "e" only fills the
  /// x-height and a "g" hangs below the baseline, so colliding on the box
  /// leaves letters floating and overlapping. This keeps the collision
  /// circle on the ink itself.
  static Rect _inkRect(String ch, TextPainter p, double fontSize) {
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

  static double _wrapAngle(double a) {
    final w = a % (2 * math.pi);
    return w > math.pi ? w - 2 * math.pi : w;
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _bounds = constraints.biggest;
          _bottomInset = MediaQuery.viewPaddingOf(context).bottom;
          return Stack(
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 12, bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _tasks.length; i++)
                              _buildRow(i),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _LettersPainter(_letters, _frame),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: Colors.white,
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 24),
            color: Colors.white,
            tooltip: 'Restore all',
            onPressed: _resetAll,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int i) {
    final task = _tasks[i];

    // Instant opacity changes keep the hand-off between real text and
    // flying letters seamless: the ghost appears the moment letters burst
    // out, and the text reappears the moment they land.
    final textOpacity = switch (task.state) {
      _TaskState.active => 1.0,
      _TaskState.done => widget.completedOpacity,
      _TaskState.restoring => 0.0,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _CheckCircle(
              checked: task.state == _TaskState.done,
              size: widget.fontSize + 5,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Opacity(
                opacity: textOpacity,
                child: Text(
                  task.title,
                  key: task.textKey,
                  style: _baseStyle.copyWith(
                    decoration: task.state == _TaskState.active
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                    decorationColor: Colors.white,
                    decorationThickness: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Check circle: an outline when open; fills white and pops a checkmark in
// when the task is done. Empties again while letters fly home.
// ---------------------------------------------------------------------------

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked, required this.size});

  final bool checked;
  final double size;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _duration,
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? Colors.white : Colors.transparent,
        border: Border.all(
          color: checked ? Colors.white : Colors.white.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: checked ? 1 : 0,
        duration: _duration,
        curve: checked ? Curves.easeOutBack : Curves.easeIn,
        child: Icon(Icons.check_rounded, size: size * 0.7, color: Colors.black),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter: draws every loose letter, rotated about its centre.
// Repaints via the frame notifier, so the widget tree never rebuilds per frame.
// ---------------------------------------------------------------------------

class _LettersPainter extends CustomPainter {
  _LettersPainter(this.letters, Listenable repaint) : super(repaint: repaint);

  final List<_Letter> letters;

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
  bool shouldRepaint(_LettersPainter oldDelegate) =>
      oldDelegate.letters != letters;
}
