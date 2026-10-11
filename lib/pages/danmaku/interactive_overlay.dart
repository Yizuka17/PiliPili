import 'dart:async';

import 'package:Pilipili/http/interactive_danmaku.dart';
import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_layout.dart';
import 'package:Pilipili/pages/danmaku/interactive_opacity.dart';
import 'package:Pilipili/plugin/pl_player/controller.dart';
import 'package:Pilipili/utils/accounts.dart';
import 'package:Pilipili/utils/accounts/account.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class InteractiveDanmakuOverlay extends StatefulWidget {
  final int aid, cid;
  final PlPlayerController player;
  final Size videoSize;
  final BoxFit fit;
  final Alignment alignment;
  final bool enabled;
  final Matrix4 transform;
  final bool flipX, flipY;
  const InteractiveDanmakuOverlay({
    super.key,
    required this.aid,
    required this.cid,
    required this.player,
    required this.videoSize,
    required this.fit,
    required this.alignment,
    required this.enabled,
    required this.transform,
    required this.flipX,
    required this.flipY,
  });
  @override
  State<InteractiveDanmakuOverlay> createState() =>
      _InteractiveDanmakuOverlayState();
}

class _InteractiveDanmakuOverlayState extends State<InteractiveDanmakuOverlay> {
  List<InteractiveDanmaku> cards = const [];
  Account? account;
  CancelToken? request;
  StreamSubscription<dynamic>? accountEvents;
  int generation = 0, progress = 0;
  Set<String> showing = {};
  @override
  void initState() {
    super.initState();
    progress = widget.player.positionInMilliseconds;
    widget.player.addPositionListener(onPosition);
    accountEvents = Accounts.account.watch().listen((_) {
      if (mounted && account != Accounts.main) unawaited(load());
    });
    unawaited(load());
  }

  @override
  void dispose() {
    generation++;
    request?.cancel();
    unawaited(accountEvents?.cancel());
    widget.player.removePositionListener(onPosition);
    super.dispose();
  }

  @override
  void didUpdateWidget(InteractiveDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removePositionListener(onPosition);
      widget.player.addPositionListener(onPosition);
    }
    if (oldWidget.aid != widget.aid ||
        oldWidget.cid != widget.cid ||
        oldWidget.player != widget.player) {
      progress = widget.player.positionInMilliseconds;
      unawaited(load());
    }
  }

  Set<String> visibleCards() =>
      cards.where((c) => c.visibleAt(progress)).map((c) => c.id).toSet();
  void onPosition(Duration value) {
    progress = value.inMilliseconds;
    if (account != Accounts.main) {
      unawaited(load());
      return;
    }
    final next = visibleCards();
    if (next.length != showing.length || !next.containsAll(showing)) {
      if (mounted) setState(() => showing = next);
    }
  }

  Future<void> load() async {
    final currentGeneration = ++generation;
    request?.cancel();
    final token = request = CancelToken();
    final currentAccount = account = Accounts.main;
    if (mounted) {
      setState(() {
        cards = const [];
        showing = {};
      });
    }
    if (widget.aid <= 0 || widget.cid <= 0) return;
    try {
      final result = await InteractiveDanmakuHttp.read(
        aid: widget.aid,
        cid: widget.cid,
        account: currentAccount,
        cancelToken: token,
      );
      if (!mounted ||
          currentGeneration != generation ||
          currentAccount != Accounts.main) {
        return;
      }
      setState(() {
        cards = result;
        showing = visibleCards();
      });
    } catch (_) {
      /* Metadata failure leaves normal video playback untouched. */
    }
  }

  bool canInteract() {
    if (account != Accounts.main) {
      unawaited(load());
      SmartDialog.showToast('账号切换，请重新选择');
      return false;
    }
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('请先登录');
      return false;
    }
    return true;
  }

  Future<InteractiveDanmaku> readCard(
    InteractiveDanmaku original,
    Account boundAccount,
  ) async {
    if (boundAccount != Accounts.main) {
      throw const InteractiveRequestFailure('账号切换');
    }
    final result = await InteractiveDanmakuHttp.read(
      aid: original.aid,
      cid: original.cid,
      account: boundAccount,
      cancelToken: request,
    );
    if (boundAccount != Accounts.main) {
      throw const InteractiveRequestFailure('账号切换');
    }
    return result.firstWhere(
      (c) =>
          c.id == original.id &&
          c.kind == original.kind &&
          c.cardId == original.cardId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final boundAccount = account;
    if (cards.isEmpty || boundAccount == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = interactiveVideoFrame(
          constraints.biggest,
          widget.videoSize,
          widget.fit,
          widget.alignment,
          transform: widget.transform,
        );
        final visibleFrame = frame.intersect(Offset.zero & constraints.biggest);
        final inView = visibleFrame.width > 16 && visibleFrame.height > 16;
        return InteractiveCardOpacity(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final card in cards)
                  CustomSingleChildLayout(
                    delegate: InteractiveCardLayout(
                      Offset(
                        widget.flipX ? 1 - card.position.dx : card.position.dx,
                        widget.flipY ? 1 - card.position.dy : card.position.dy,
                      ),
                      frame,
                    ),
                    child: InteractiveDanmakuCard(
                      key: ValueKey('$generation-${card.id}'),
                      initial: card,
                      visible:
                          widget.enabled && inView && showing.contains(card.id),
                      progress: () => widget.player.positionInMilliseconds,
                      pause: () => widget.player.pause(),
                      canInteract: canInteract,
                      read: () => readCard(card, boundAccount),
                      submit: (fresh, choice, milliseconds) async {
                        if (boundAccount != Accounts.main) {
                          throw const InteractiveRequestFailure('账号切换');
                        }
                        await InteractiveDanmakuHttp.submit(
                          fresh,
                          choice,
                          milliseconds,
                          account: boundAccount,
                        );
                      },
                      notify: SmartDialog.showToast,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
