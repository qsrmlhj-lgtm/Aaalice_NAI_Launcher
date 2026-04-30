class WindowFocusTracker {
  WindowFocusTracker._();

  static DateTime? _lastFocusedAt;
  static DateTime? _lastBlurredAt;

  static DateTime? get lastFocusedAt => _lastFocusedAt;
  static DateTime? get lastBlurredAt => _lastBlurredAt;

  static void markFocused([DateTime? at]) {
    _lastFocusedAt = at ?? DateTime.now();
  }

  static void markBlurred([DateTime? at]) {
    _lastBlurredAt = at ?? DateTime.now();
  }

  static Duration? elapsedSinceFocus({DateTime? now}) {
    final focusedAt = _lastFocusedAt;
    if (focusedAt == null) return null;
    return (now ?? DateTime.now()).difference(focusedAt);
  }

  static Duration? elapsedSinceBlur({DateTime? now}) {
    final blurredAt = _lastBlurredAt;
    if (blurredAt == null) return null;
    return (now ?? DateTime.now()).difference(blurredAt);
  }

  static bool isWithinCooldown(Duration cooldown, {DateTime? now}) {
    final elapsed = elapsedSinceFocus(now: now);
    if (elapsed == null) return false;
    return elapsed <= cooldown;
  }

  static bool hadRecentFocusBounce({
    Duration maxSinceFocus = const Duration(seconds: 4),
    Duration maxSinceBlur = const Duration(seconds: 8),
    DateTime? now,
  }) {
    final focusedAt = _lastFocusedAt;
    final blurredAt = _lastBlurredAt;
    if (focusedAt == null || blurredAt == null) return false;
    if (!focusedAt.isAfter(blurredAt)) return false;

    final current = now ?? DateTime.now();
    final focusElapsed = current.difference(focusedAt);
    final blurElapsed = current.difference(blurredAt);
    return focusElapsed <= maxSinceFocus && blurElapsed <= maxSinceBlur;
  }
}
