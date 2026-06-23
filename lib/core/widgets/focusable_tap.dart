import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any widget in a focusable, D-pad-activatable region for Android TV.
///
/// Primary input is the D-pad remote: select/enter/gameButtonA activate [onTap],
/// and the MENU key activates [onMenu] for secondary actions (e.g. favourite).
///
/// Mouse clicks (emulator) are also handled via [GestureDetector].
/// Long-press is intentionally removed — TV remotes cannot hold a button.
///
/// Used by:
/// - [ChannelCard]
/// - [_CircleNavButton] in `app_nav_bar.dart`
/// - [CtrlBtn]          in `player/widgets/ctrl_btn.dart`
/// - [IconAction]       in `player/widgets/icon_action.dart`
/// - [_SidebarItem]     in `player/widgets/channel_list_panel.dart`
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.builder,
    this.onMenu,
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback onTap;

  /// TV remote MENU button (KEYCODE_MENU / LogicalKeyboardKey.contextMenu).
  /// Use for secondary actions (e.g. favourite) unreachable via D-pad select.
  final VoidCallback? onMenu;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Called every build with the current focus state.
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        setState(() => _focused = v);
        if (!v) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || Scrollable.maybeOf(context) == null) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.08,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        });
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.gameButtonA) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (widget.onMenu != null && k == LogicalKeyboardKey.contextMenu) {
          widget.onMenu!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // GestureDetector kept for emulator mouse-click testing.
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
