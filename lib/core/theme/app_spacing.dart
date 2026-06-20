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

  /// Fixed row height of a player-sidebar channel tile (must match the
  /// ListView itemExtent so jump-to-current scrolling stays accurate).
  static const tvSidebarTile = 72.0;

  /// Fixed cell height of a channel card in the home + channels grids.
  static const tvGridCardExtent = 168.0;

  /// Max width of a grid card. Grids size cards by this (not a fixed column
  /// count), so the layout stays responsive across 720p/1080p/4K panels.
  static const tvGridCardMaxExtent = 220.0;

  /// Width of the player channel-list sidebar panel.
  static const tvSidebarWidth = 320.0;

  // ── Border radii — sharper, more cinematic ─────────────────────────────────
  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 18.0;
  static const radiusXl = 24.0;

  // ── Icon sizes ───────────────────────────────────────────────────────────
  static const iconSm = 20.0;
  static const iconMd = 28.0;
  static const iconLg = 34.0;

  // ── Logo / brand mark ────────────────────────────────────────────────────
  static const logoSize = 68.0;
  static const logoRadius = 22.0;
}
