import 'package:flutter/material.dart';

/// Unfocuses the primary focus node if it belongs to a text-input widget.
///
/// Returns `true` if a text field was focused and has now been dismissed,
/// `false` if no text field was active (caller should proceed with navigation).
///
/// Usage inside a [PopScope.onPopInvokedWithResult]:
/// ```dart
/// if (_dismissKeyboardIfOpen()) return; // stay on screen, keyboard gone
/// context.go('/');                      // nothing focused — navigate away
/// ```
bool dismissKeyboardIfOpen() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return false;
  final ctx = focus.context;
  if (ctx == null) return false;
  // Walk up the widget tree to see if an EditableText owns this focus node.
  final isTextField =
      ctx.findAncestorStateOfType<EditableTextState>() != null;
  if (isTextField) {
    focus.unfocus();
    return true;
  }
  return false;
}
