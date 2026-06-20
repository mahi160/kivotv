import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges a [ValueNotifier] to a Riverpod stream.
///
/// Emits the current value immediately (so first-watch rebuilds right away),
/// then re-emits on every change. The listener + controller are torn down with
/// the owning provider via [ref.onDispose].
Stream<T> valueNotifierStream<T>(Ref ref, ValueNotifier<T> notifier) {
  final controller = StreamController<T>();
  controller.add(notifier.value);

  void listener() => controller.add(notifier.value);
  notifier.addListener(listener);

  ref.onDispose(() {
    notifier.removeListener(listener);
    controller.close();
  });

  return controller.stream;
}
