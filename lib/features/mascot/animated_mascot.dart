import 'package:flutter/material.dart';

import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import 'mascot_expression.dart';

/// Which expression art set to draw. Both sets use the same filenames
/// (`<mood>.png`); sizes are matched by the character's visible height,
/// not the PNG canvas (calorie art canvases are squarer). Each set
/// carries its own horizontal stretch (art is never redrawn, only
/// scaled relatively).
enum MascotArtSet {
  // Water art: +12% base stretch, then +2mm (1.245), then +3mm more per
  // Niko (~16.9 logical px at 2.8125 dpr on a ~90px canvas → +0.187).
  water('assets/images/expressions/', 1.43),
  calorie('assets/images/expressions/calorie/', 1.12);

  const MascotArtSet(this.base, this.widthStretch);
  final String base;
  final double widthStretch;
}

/// Shows Lil Drop's current expression and plays a cozy squish-fade
/// whenever [expression] changes, on top of a gentle breathing bob.
///
/// Motion only — the artwork comes from Niko's PNGs via
/// [moodBuilder] (defaults to the bundled expression assets).
class AnimatedMascot extends StatefulWidget {
  const AnimatedMascot({
    super.key,
    required this.expression,
    this.moodBuilder,
    this.artSet = MascotArtSet.water,
    this.size = 132,
    this.duration = const Duration(milliseconds: 340),
  });

  final MascotExpression expression;

  /// Optional override for where the visuals come from (used by tests
  /// with placeholder chips). Defaults to the bundled expression PNGs.
  final Widget Function(BuildContext context, MascotExpression expression)?
      moodBuilder;

  /// Which art set to draw from (water page vs calorie page).
  final MascotArtSet artSet;

  /// Height of the expression image. Width is a slight stretch wider
  /// than the natural aspect (Niko: "overall bigger, width a bit longer").
  final double size;
  final Duration duration;

  @override
  State<AnimatedMascot> createState() => _AnimatedMascotState();
}

class _AnimatedMascotState extends State<AnimatedMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: _bobCycle,
  )..repeat(reverse: true);

  // Motion parameters per expression (kept subtle, never cutesy).
  Duration get _bobCycle => widget.expression == MascotExpression.sleeping
      ? const Duration(milliseconds: 2600)
      : const Duration(milliseconds: 1400);

  double get _bobExtent => widget.expression == MascotExpression.excited
      ? 4
      : 1.5;

  double get _tilt => widget.expression == MascotExpression.sleeping
      ? 0.10
      : 0.0;

  @override
  void didUpdateWidget(AnimatedMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expression != oldWidget.expression &&
        _bob.duration != _bobCycle) {
      _bob.duration = _bobCycle;
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  Widget _defaultArt(BuildContext context, MascotExpression expression) {
    // Relative widening: every PNG keeps its own natural aspect and gets
    // the art set's horizontal stretch. (An absolute width stretched the
    // narrow idle art way more than the others.)
    return Transform.scale(
      scaleX: widget.artSet.widthStretch,
      child: Image.asset(
        '${widget.artSet.base}${expression.name}.png',
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none, // crisp pixel scaling
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The bob wraps the whole switcher so old and new visuals breathe
    // together while the squish-fade transition plays.
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_bob.value);
        return Transform.translate(
          offset: Offset(0, -_bobExtent * t),
          child: Transform.rotate(
            angle: _tilt * t,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: AnimatedSwitcher(
        duration: widget.duration,
        switchInCurve: Curves.easeOutBack, // overshoot = squishy pop
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey<MascotExpression>(widget.expression),
          child: widget.moodBuilder != null
              ? widget.moodBuilder!(context, widget.expression)
              : _defaultArt(context, widget.expression),
        ),
      ),
    );
  }
}

/// Temporary stand-in visuals (one cozy chip per expression), used by
/// widget tests so they do not depend on asset loading.
class MascotPlaceholder extends StatelessWidget {
  const MascotPlaceholder({super.key, required this.expression, this.size});

  final MascotExpression expression;
  final double? size;

  static const _looks = {
    MascotExpression.idle: (Color(0xFFA9C9E8), 'Idle'), // sky
    MascotExpression.excited: (Color(0xFFF7B98B), 'Excited'), // peach
    MascotExpression.loved: (Color(0xFFF3A7B4), 'Loved'), // blush
    MascotExpression.worried: (Color(0xFFDCEAF6), 'Worried'), // skySoft
    MascotExpression.angry: (Color(0xFFE89A63), 'Angry'), // peachDeep
    MascotExpression.sleeping: (Color(0xFF8A7461), 'Zzz'), // cocoaSoft
  };

  @override
  Widget build(BuildContext context) {
    final (fill, label) = _looks[expression]!;
    final size = this.size;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.outline, width: 2),
        boxShadow: const [
          BoxShadow(color: Palette.shadow, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTypography.pixelDisplay(
          12,
          color: expression == MascotExpression.angry ||
                  expression == MascotExpression.sleeping
              ? Palette.paper
              : Palette.cocoa,
        ),
      ),
    );
  }
}
