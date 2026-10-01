# Floating Text

Tap a task and its letters break free, tumble, and pile up.
Tilt the phone to slosh them around (lay it flat and they float).
Tap the task again, or the restore button, to fly the letters home.

On simulators, desktop, and web there is no tilt sensor, so letters fall straight down.

## How the animations work

Think of the screen as two layers: the task list you tap, and a transparent sheet on top where loose letters live.

**Opening the list.** Rows do not appear all at once. The first task fades and slides in, then the next, then the next — like people walking on stage one after another.

**Pressing a row.** The row shrinks a little under your finger, then springs back. That is the only “button press” feel.

**Completing a task.** Two things happen together:
1. The checkbox fills white and a checkmark pops in.
2. The real text is swapped for a faint struck-through ghost. At the same instant, each letter is copied onto the overlay, tossed upward with a bit of spin, and handed to a tiny physics world.

From there the letters are not “playing a canned animation.” They behave like small objects: gravity pulls them down, air slows them, they bounce off the floor and each other, and they settle into a pile. Tilt the phone and gravity tilts with you, so the pile sloshes. Lay the phone flat and they almost float.

**Putting letters back.** Tap the task again (or the refresh button). Physics lets go. Each letter glides home to the exact spot it came from, starting from the left of the word so they return in reading order. The checkmark empties, the real text reappears as they land, and the refresh icon spins once if you used restore-all.

**Why it stays smooth.** The pile is drawn as one picture on that overlay, not as hundreds of separate text widgets. The list underneath is not rebuilt every frame — only the letters are redrawn.

## Run

```bash
flutter pub get
flutter run
```

Requires Flutter 3.27+ (`Color.withValues`) and Dart 3. Device tilt uses `sensors_plus`.

```bash
flutter analyze
flutter test
```

## Layout

```
lib/
  main.dart                 App shell
  floating_text_tasks.dart  Task list screen
  models.dart               Task, Letter, Glyph
  letter_simulation.dart    Physics pile and restore motion
  glyph_layout.dart         Character measurement
  widgets/
    check_circle.dart
    task_header.dart
    task_row.dart
    letters_painter.dart
```
