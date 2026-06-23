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
  static const tvEdge = 48.0;

  /// Slightly tighter edge for sub-screens (channel list, settings).
  static const tvEdgeSm = 34.0;

  /// Vertical gap below the screen header row.
  static const tvHeaderGap = 18.0;

  /// Fixed row height of a player-sidebar channel tile (must match the
  /// ListView itemExtent so jump-to-current scrolling stays accurate).
  static const tvSidebarTile = 58.0;

  /// Fixed cell height of a channel card in the channels grid. Tall enough for
  /// the logo band + the name/group footer of the redesigned card.
  static const tvGridCardExtent = 174.0;

  /// Max width of a grid card. Grids size cards by this (not a fixed column
  /// count), so the layout stays responsive across 720p/1080p/4K panels.
  static const tvGridCardMaxExtent = 232.0;

  /// Home carousel ("Netflix row") card footprint. Cards are a fixed size in
  /// a horizontal ListView so the row reads as one clean band of equal tiles.
  static const tvRowCardWidth = 220.0;
  static const tvRowCardHeight = 156.0;

  /// Compact Live-match card: small logo + name on a slim single-line tile,
  /// much shorter than a poster card so the Live row reads as a thin band.
  static const tvLiveCardWidth = 248.0;
  static const tvLiveCardHeight = 58.0;

  /// Height of the tinted logo band at the top of a channel card.
  static const tvCardLogoBand = 82.0;

  /// Height of the persistent top nav bar.
  static const tvHeaderHeight = 58.0;

  /// Gap between cards inside a home row.
  static const tvRowGap = 14.0;

  /// Vertical gap between one home section and the next.
  static const tvSectionGap = 30.0;

  /// Width of the player channel-list sidebar panel.
  static const tvSidebarWidth = 320.0;

  // ── Border radii — sharper, more cinematic ─────────────────────────────────
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 20.0;

  // ── Icon sizes ───────────────────────────────────────────────────────────
  static const iconSm = 20.0;
  static const iconMd = 28.0;
  static const iconLg = 34.0;

  // ── Logo / brand mark ────────────────────────────────────────────────────
  static const logoSize = 68.0;
  static const logoRadius = 22.0;
}
