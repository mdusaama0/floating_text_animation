import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

const double kPxPerG = 100; // gravityStrength 15 → 1500 px/s² at 1g
const double kRestitution = 0.25; // bounciness
const double kWallFriction = 0.92; // tangential damping on wall contact
const double kAirDrag = 0.35; // per second
const double kImpactThreshold = 40; // px/s; softer contacts don't bounce
const double kSpinDrag = 4; // per second: a tossed letter turns, then stops
const double kContactSpinDamp = 0.85; // per substep while touching something
const double kImpactKick = 0.008; // rad/s of spin per px/s of hard impact
const int kPhysicsSubsteps = 3; // physics steps per frame
const int kSolverIterations = 4; // contact passes per step; more = firmer pile
const double kLetterGap = 1.5; // px of breathing room around each letter

final CurveTween kRestoreCurve = CurveTween(curve: Curves.easeInOutCubic);

class LetterSimulation {
  LetterSimulation({math.Random? rng}) : rng = rng ?? math.Random();

  final math.Random rng;
  Size bounds = Size.zero;
  double bottomInset = 0;
  Offset gravity = const Offset(0, 1);

  void tick(List<Letter> letters, double dt, double gravityStrength) {
    final h = dt / kPhysicsSubsteps;
    for (var s = 0; s < kPhysicsSubsteps; s++) {
      _simulate(letters, h, gravityStrength);
    }
  }

  void _simulate(List<Letter> letters, double h, double gravityStrength) {
    final g = gravity * (gravityStrength * kPxPerG);
    final bodies = [
      for (final l in letters)
        if (!l.restoring) l,
    ];

    for (final l in bodies) {
      l.vel = (l.vel + g * h) * (1 - kAirDrag * h);
      l.pos += l.vel * h;
      l.angle += l.spin * h;
      l.spin *= 1 - kSpinDrag * h;
      l.touching = false;
    }

    // Several contact passes per step. With a single pass, the weight of a
    // deep pile squashed the bottom rows into each other; repeating the
    // separation lets every layer push back fully. Only the first pass
    // changes velocities (bounces, friction, knocks); the rest just
    // untangle positions.
    for (var it = 0; it < kSolverIterations; it++) {
      final first = it == 0;
      _solveContacts(bodies, first);
      for (final l in bodies) {
        _collideWalls(l, first);
      }
    }

    for (final l in bodies) {
      // Anything resting on something stops turning almost at once.
      if (l.touching) l.spin *= kContactSpinDamp;
    }
  }

  /// Finds touching pairs with a uniform grid (each letter only checks its
  /// neighbouring cells) instead of testing every pair, so extra solver
  /// passes stay cheap even with a couple of hundred letters.
  void _solveContacts(List<Letter> bodies, bool withVelocity) {
    if (bodies.length < 2) return;
    var maxR = 0.0;
    for (final l in bodies) {
      if (l.radius > maxR) maxR = l.radius;
    }
    final cell = maxR * 2;

    final grid = <int, List<Letter>>{};
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

  void _collidePair(Letter a, Letter b, bool withVelocity) {
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
    final hard = -vn > kImpactThreshold;
    final e = hard ? kRestitution : 0.0;
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
      (rng.nextDouble() * 2 - 1) * math.min(impact, 400) * kImpactKick;

  void _collideWalls(Letter l, bool withVelocity) {
    final r = l.radius;
    var x = l.pos.dx, y = l.pos.dy, vx = l.vel.dx, vy = l.vel.dy;
    var impact = 0.0;
    // Later solver passes only fix positions; friction is applied once.
    final friction = withVelocity ? kWallFriction : 1.0;

    final floor = bounds.height - bottomInset;
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
    if (x > bounds.width - r) {
      x = bounds.width - r;
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
    if (impact > kImpactThreshold) l.spin += _knock(impact);
  }

  double _bounce(double v) {
    final out = -v * kRestitution;
    return out.abs() < 25 ? 0 : out; // kill micro-bounces so piles settle
  }
}

/// Advances staggered restore tweens. Returns true if any letter finished.
bool advanceLetterRestores({
  required List<Letter> letters,
  required double dt,
  required Duration restoreDuration,
}) {
  final secs = restoreDuration.inMicroseconds / 1e6;
  final step = secs <= 0 ? 1.0 : dt / secs;
  var anyFinished = false;

  letters.removeWhere((l) {
    if (!l.restoring) return false;
    l.restoreClock += step;
    final t = ((l.restoreClock - l.restoreDelay) / 0.7)
        .clamp(0.0, 1.0)
        .toDouble();
    final e = kRestoreCurve.transform(t);
    l.pos = l.restorePos!.transform(e);
    l.angle = l.restoreAngle!.transform(e);
    if (l.restoreClock < 1) return false;
    l.painter.dispose();
    anyFinished = true;
    return true;
  });

  return anyFinished;
}

double wrapAngle(double a) {
  final w = a % (2 * math.pi);
  return w > math.pi ? w - 2 * math.pi : w;
}
