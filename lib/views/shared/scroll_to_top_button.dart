import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

/// A floating "scroll to top" button.
/// It stays hidden until [controller] is scrolled past [threshold],
/// then fades/scales in. Tapping it smoothly animates back to the top.
class ScrollToTopButton extends StatefulWidget {
  final ScrollController controller;
  final double threshold;

  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold = 300,
  });

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  void _handleScroll() {
    final shouldShow = widget.controller.hasClients &&
        widget.controller.offset > widget.threshold;
    if (shouldShow != _visible) {
      setState(() => _visible = shouldShow);
    }
  }

  void _scrollToTop() {
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: AnimatedScale(
          scale: _visible ? 1 : 0.7,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Tooltip(
            message: 'Scroll to top',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _scrollToTop,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: MediColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: MediColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}