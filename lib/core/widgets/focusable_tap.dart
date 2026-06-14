import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any widget in a focusable, D-pad-activatable tap region.
///
/// Handles the identical boilerplate that was duplicated across six widgets:
/// - [ChannelCard]
/// - [_NavIcon]       in `app_nav_bar.dart`
/// - [_ThemeOption]   in `settings_screen.dart`
/// - [CtrlBtn]        in `player/widgets/ctrl_btn.dart`
/// - [IconAction]     in `player/widgets/icon_action.dart`
/// - [_SidebarItem]   in `player/widgets/channel_list_panel.dart`
///
/// [builder] receives the current focus state so the caller controls visuals.
/// Calls [onTap] on pointer tap OR D-pad select/enter.
///
/// Example:
/// ```dart
/// FocusableTap(
///   onTap: () => doSomething(),
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
    this.focusNode,
    this.autofocus = false,
  });

  final VoidCallback  onTap;
  final VoidCallback? onLongPress;
  final FocusNode?    focusNode;
  final bool          autofocus;

  /// Called every time focus changes. Receives `(BuildContext, bool focused)`.
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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap:      widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
