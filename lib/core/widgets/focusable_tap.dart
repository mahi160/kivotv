import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any widget in a focusable, D-pad-activatable tap region.
///
/// Handles the identical boilerplate that was duplicated across six widgets:
/// - [ChannelCard]
/// - [_NavIcon]       in `app_nav_bar.dart`
/// - [CtrlBtn]        in `player/widgets/ctrl_btn.dart`
/// - [IconAction]     in `player/widgets/icon_action.dart`
/// - [_SidebarItem]   in `player/widgets/channel_list_panel.dart`
///
/// [builder] receives the current focus state so the caller controls visuals.
/// Calls [onTap] on pointer tap OR D-pad select/enter.
/// Calls [onMenu] on the TV remote MENU key (KEYCODE_MENU / contextMenu).
/// Calls [onLongPress] on pointer long-press (touch only — remotes can't hold).
///
/// Example:
/// ```dart
/// FocusableTap(
///   onTap:  () => openChannel(),
///   onMenu: () => toggleFavourite(),
///   builder: (context, focused) => AnimatedContainer(
///     color: focused ? Colors.blue : Colors.grey,
///     child: const Text('Press me'),
///   ),
/// )
/// ```
class FocusableTap extends StatefulWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.builder,
    this.onLongPress,
    this.onMenu,
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback  onTap;
  /// Pointer long-press (touch devices). Does NOT fire from a D-pad hold.
  final VoidCallback? onLongPress;
  /// TV remote MENU button (KEYCODE_MENU / LogicalKeyboardKey.contextMenu).
  /// Use this for secondary actions (e.g. favourite) that are unreachable
  /// via long-press on a standard TV remote.
  final VoidCallback? onMenu;
  final FocusNode?    focusNode;
  final bool          autofocus;

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
      focusNode:     widget.focusNode,
      autofocus:     widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (widget.onMenu != null && k == LogicalKeyboardKey.contextMenu) {
          widget.onMenu!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap:       widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
