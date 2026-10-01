import 'package:flutter/material.dart';

class CheckCircle extends StatefulWidget {
  const CheckCircle({super.key, required this.checked, required this.size});

  final bool checked;
  final double size;

  static const duration = Duration(milliseconds: 220);

  @override
  State<CheckCircle> createState() => _CheckCircleState();
}

class _CheckCircleState extends State<CheckCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _fill;
  late final Animation<Color?> _border;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CheckCircle.duration,
      value: widget.checked ? 1 : 0,
    );
    final motion = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    _fill = ColorTween(
      begin: Colors.transparent,
      end: Colors.white,
    ).animate(motion);
    _border = ColorTween(
      begin: Colors.white.withValues(alpha: 0.55),
      end: Colors.white,
    ).animate(motion);
    _checkScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
  }

  @override
  void didUpdateWidget(CheckCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked == widget.checked) return;
    if (widget.checked) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: Icon(
        Icons.check_rounded,
        size: widget.size * 0.7,
        color: Colors.black,
      ),
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _fill.value,
            border: Border.all(color: _border.value!, width: 1.5),
          ),
          child: Transform.scale(scale: _checkScale.value, child: child),
        );
      },
    );
  }
}
