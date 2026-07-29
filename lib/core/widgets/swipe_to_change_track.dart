import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';

/// Wraps [child] so a horizontal swipe skips track: left for next, right for
/// previous — the direction the artwork would travel.
///
/// Shared by the mini player and the full player so the gesture means the same
/// thing in both.
class SwipeToChangeTrack extends ConsumerStatefulWidget {
  const SwipeToChangeTrack({
    super.key,
    required this.child,
    this.dragToDismissDistance = 64,
  });

  final Widget child;

  /// How far the finger must travel before the swipe counts, when it is too
  /// slow to be judged by velocity alone.
  final double dragToDismissDistance;

  @override
  ConsumerState<SwipeToChangeTrack> createState() => _SwipeToChangeTrackState();
}

class _SwipeToChangeTrackState extends ConsumerState<SwipeToChangeTrack>
    with SingleTickerProviderStateMixin {
  // Built in initState, not as a lazy `late final` initialiser: a swipe that
  // never happens (open the player, navigate straight back) meant this was
  // never touched until dispose() read it for the first time there — by then
  // the element is deactivating, and creating a ticker looks up an ancestor
  // that is no longer safe to look up, throwing instead of disposing cleanly.
  late final AnimationController _controller;

  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // Resist the drag, so the content follows the finger without sliding right
    // off the screen — this is a gesture, not a page turn.
    setState(() => _offset = (_offset + details.delta.dx * 0.5).clamp(-80, 80));
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;
    final handler = ref.read(audioHandlerProvider);

    final goNext = velocity < -250 || _offset <= -widget.dragToDismissDistance;
    final goPrevious =
        velocity > 250 || _offset >= widget.dragToDismissDistance;

    if (goNext) {
      await handler.skipToNext();
    } else if (goPrevious) {
      await handler.skipToPrevious();
    }

    await _settle();
  }

  /// Spring the content back to centre whether or not the swipe took.
  Future<void> _settle() async {
    final from = _offset;
    final animation = Tween<double>(begin: from, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    void listener() => setState(() => _offset = animation.value);
    animation.addListener(listener);

    await _controller.forward(from: 0);
    animation.removeListener(listener);

    if (mounted) setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so the gesture is caught over empty space too, not just the art.
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_offset, 0),
        child: widget.child,
      ),
    );
  }
}
