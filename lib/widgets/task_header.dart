import 'package:flutter/material.dart';

class TaskHeader extends StatelessWidget {
  const TaskHeader({
    super.key,
    required this.title,
    required this.onRestoreAll,
  });

  final String title;
  final VoidCallback onRestoreAll;

  @override
  Widget build(BuildContext context) {
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
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          RestoreAllButton(onPressed: onRestoreAll),
        ],
      ),
    );
  }
}

class RestoreAllButton extends StatefulWidget {
  const RestoreAllButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<RestoreAllButton> createState() => _RestoreAllButtonState();
}

class _RestoreAllButtonState extends State<RestoreAllButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// 0 turns → 1 turn (360°). Restarted from 0 on every tap.
  late final Animation<double> _turns = Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePressed() {
    widget.onPressed();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: RotationTransition(
        turns: _turns,
        child: const Icon(Icons.refresh_rounded, size: 24),
      ),
      color: Colors.white,
      tooltip: 'Restore all',
      onPressed: _handlePressed,
    );
  }
}
