/// Layout spacing tokens for Kivo.
///
/// Use these constants everywhere instead of magic numbers so padding
/// and sizing can be updated in one place.
abstract final class AppSpacing {
  // ── Base scale ───────────────────────────────────────────────────────────
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 14.0;
  static const md = 24.0;
  static const lg = 34.0;
  static const xl = 48.0;
  static const xxl = 64.0;

  // ── TV-specific layout ───────────────────────────────────────────────────
  /// Horizontal/vertical edge padding from screen border.
  static const tvEdge = 40.0;

  /// Slightly tighter edge for sub-screens (channel list, settings).
  static const tvEdgeSm = 34.0;

  /// Vertical gap below the screen header row.
  static const tvHeaderGap = 28.0;

  /// Height of a channel list tile.
  static const tvTileHeight = 86.0;

  /// Width of a horizontal channel card (home dashboard rows).
  static const tvCardWidth = 250.0;

  /// Height of a horizontal scroll row on the home dashboard.
  static const tvRowHeight = 156.0;

  /// Gap between cards inside a horizontal row.
  static const tvCardGap = 14.0;

  // ── Border radii ─────────────────────────────────────────────────────────
  static const radiusSm = 16.0;
  static const radiusMd = 22.0;
  static const radiusLg = 26.0;
  static const radiusXl = 30.0;

  // ── Icon sizes ───────────────────────────────────────────────────────────
  static const iconSm = 20.0;
  static const iconMd = 28.0;
  static const iconLg = 34.0;

  // ── Logo / brand mark ────────────────────────────────────────────────────
  static const logoSize = 68.0;
  static const logoRadius = 22.0;
}
