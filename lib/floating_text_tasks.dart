import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'glyph_layout.dart';
import 'letter_simulation.dart';
import 'models.dart';
import 'widgets/letters_painter.dart';
import 'widgets/task_header.dart';
import 'widgets/task_row.dart';

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

class _FloatingTextTasksState extends State<FloatingTextTasks>
    with TickerProviderStateMixin {
  late final List<Task> _tasks = [for (final t in widget.tasks) Task(t)];
  final List<Letter> _letters = [];
  final GlobalKey _stackKey = GlobalKey();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final LetterSimulation _sim = LetterSimulation();

  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _entrance;
  late final List<Animation<double>> _rowFades;
  late final List<Animation<Offset>> _rowSlides;

  Duration _lastTick = Duration.zero;
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
    _initEntrance();
    _listenToMotion();
  }

  void _initEntrance() {
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final n = math.max(_tasks.length, 1);
    _rowFades = [
      for (var i = 0; i < _tasks.length; i++)
        CurvedAnimation(
          parent: _entrance,
          curve: Interval(
            (i / n) * 0.45,
            ((i / n) * 0.45 + 0.55).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
    ];
    _rowSlides = [
      for (final fade in _rowFades)
        Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(fade),
    ];
    _entrance.forward();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    _entrance.dispose();
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
              _sim.gravity = Offset.lerp(
                _sim.gravity,
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
      case TaskState.active:
        _complete(i);
      case TaskState.done:
        _restore(i);
      case TaskState.restoring:
        break;
    }
  }

  void _resetAll() {
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].state == TaskState.done) _restore(i);
    }
  }

  void _complete(int i) {
    final layout = layoutGlyphs(
      task: _tasks[i],
      stackKey: _stackKey,
      baseStyle: _baseStyle,
      fontSize: widget.fontSize,
    );
    if (layout == null) return;

    for (final g in layout.glyphs) {
      final painter = TextPainter(
        text: TextSpan(text: g.char, style: layout.style),
        textDirection: layout.direction,
        textScaler: layout.scaler,
      )..layout();

      final ink = inkRect(
        g.char,
        painter,
        layout.scaler.scale(widget.fontSize),
      );
      final letter = Letter(
        task: i,
        offset: g.offset,
        painter: painter,
        // Circle around the whole visible glyph plus a small gap, so
        // letters in the pile sit next to each other instead of overlapping.
        radius:
            math.max(3.0, 0.5 * math.max(ink.width, ink.height)) + kLetterGap,
        anchor: ink.center,
        pos: g.rect.topLeft + ink.center,
      );

      // Burst mostly upward with a random spread, and a random toss of
      // rotation. Drag stops the turn after at most ~80°, so letters land
      // at scattered angles without ever spinning continuously.
      final dir = -math.pi / 2 + (_sim.rng.nextDouble() - 0.5) * math.pi * 1.1;
      final speed = widget.scatterStrength * (30 + _sim.rng.nextDouble() * 70);
      letter.vel = Offset(math.cos(dir), math.sin(dir)) * speed;
      letter.spin =
          (_sim.rng.nextDouble() * 2 - 1) * (1.5 + widget.scatterStrength * 0.9);

      _letters.add(letter);
    }

    setState(() => _tasks[i].state = TaskState.done);
    _startTicker();
  }

  void _restore(int i) {
    final layout = layoutGlyphs(
      task: _tasks[i],
      stackKey: _stackKey,
      baseStyle: _baseStyle,
      fontSize: widget.fontSize,
    );
    final homes = {
      for (final g in layout?.glyphs ?? const <Glyph>[])
        g.offset: g.rect.topLeft,
    };

    final mine = _letters.where((l) => l.task == i).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));

    if (mine.isEmpty) {
      setState(() => _tasks[i].state = TaskState.active);
      return;
    }

    for (var k = 0; k < mine.length; k++) {
      final l = mine[k];
      final home = homes[l.offset] == null
          ? l.pos
          : homes[l.offset]! + l.anchor;
      l
        ..restoring = true
        ..restoreClock = 0
        // Stagger left-to-right across the first 30% of the duration.
        ..restoreDelay = mine.length == 1 ? 0 : 0.3 * k / (mine.length - 1)
        ..restorePos = Tween<Offset>(begin: l.pos, end: home)
        ..restoreAngle = Tween<double>(begin: wrapAngle(l.angle), end: 0)
        ..vel = Offset.zero;
    }

    setState(() => _tasks[i].state = TaskState.restoring);
    _startTicker();
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
    if (dt <= 0 || _sim.bounds.isEmpty) return;

    _sim.tick(_letters, dt, widget.gravityStrength);
    final anyFinished = advanceLetterRestores(
      letters: _letters,
      dt: dt,
      restoreDuration: widget.restoreDuration,
    );

    _frame.value++;
    if (_letters.isEmpty) _ticker.stop();
    if (!anyFinished) return;

    final stillOut = {for (final l in _letters) l.task};
    setState(() {
      for (var i = 0; i < _tasks.length; i++) {
        if (_tasks[i].state == TaskState.restoring && !stillOut.contains(i)) {
          _tasks[i].state = TaskState.active;
        }
      }
    });
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          _sim.bounds = constraints.biggest;
          _sim.bottomInset = MediaQuery.viewPaddingOf(context).bottom;
          return Stack(
            key: _stackKey,
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TaskHeader(title: widget.title, onRestoreAll: _resetAll),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 12, bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _tasks.length; i++)
                              TaskRow(
                                task: _tasks[i],
                                fontSize: widget.fontSize,
                                completedOpacity: widget.completedOpacity,
                                style: _baseStyle,
                                fade: _rowFades[i],
                                slide: _rowSlides[i],
                                onTap: () => _toggle(i),
                              ),
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
                      painter: LettersPainter(_letters, _frame),
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
}
