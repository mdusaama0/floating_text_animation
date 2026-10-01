import 'package:flutter/material.dart';

import '../models.dart';
import 'check_circle.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.fontSize,
    required this.completedOpacity,
    required this.style,
    required this.fade,
    required this.slide,
    required this.onTap,
  });

  final Task task;
  final double fontSize;
  final double completedOpacity;
  final TextStyle style;
  final Animation<double> fade;
  final Animation<Offset> slide;
  final VoidCallback onTap;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Instant opacity keeps the hand-off between real text and flying
    // letters seamless: the ghost appears the moment letters burst out,
    // and the text reappears the moment they land.
    final textOpacity = switch (widget.task.state) {
      TaskState.active => 1.0,
      TaskState.done => widget.completedOpacity,
      TaskState.restoring => 0.0,
    };

    return FadeTransition(
      opacity: widget.fade,
      child: SlideTransition(
        position: widget.slide,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CheckCircle(
                    checked: widget.task.state == TaskState.done,
                    size: widget.fontSize + 5,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Opacity(
                      opacity: textOpacity,
                      child: Text(
                        widget.task.title,
                        key: widget.task.textKey,
                        style: widget.style.copyWith(
                          decoration: widget.task.state == TaskState.active
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
          ),
        ),
      ),
    );
  }
}
