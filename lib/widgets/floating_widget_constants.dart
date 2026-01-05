/// Constants for the floating widget dimensions and styling
///
/// This file centralizes all magic numbers used in the floating widget
/// to make the code more maintainable and easier to understand.
class FloatingWidgetConstants {
  // Prevent instantiation - this is a utility class
  FloatingWidgetConstants._();

  // ============================================================================
  // WINDOW DIMENSIONS
  // ============================================================================

  /// Width of the window when collapsed (showing only icon)
  static const double collapsedWidth = 30.0;

  /// Width of the window when expanded (showing full content)
  static const double expandedWidth = 280.0;

  /// Base height of the window (without dropdown list)
  /// Calculated as: mainRowHeight (70) + borders/shadows (10) = 80px minimum
  static const double baseHeight = 80.0;

  /// Maximum height for the project dropdown list
  static const double maxDropdownHeight = 300.0;

  /// Height of each project item in the dropdown (collapsed state)
  static const double projectItemHeight = 66.0;

  // ============================================================================
  // SPACING & PADDING
  // ============================================================================

  /// Horizontal padding when widget is collapsed
  /// Must be 0 to fit within 60px window width constraint
  static const double collapsedHorizontalPadding = 0.0;

  /// Horizontal padding when widget is expanded
  static const double expandedHorizontalPadding = 12.0;

  /// Vertical padding for the main container
  static const double verticalPadding = 8.0;

  /// Height of the main row containing icon and content
  static const double mainRowHeight = 70.0;

  /// Spacing between icon and text content
  static const double iconTextSpacing = 10.0;

  /// Spacing between project icon and name in dropdown
  static const double dropdownIconSpacing = 10.0;

  /// Horizontal padding for dropdown items
  static const double dropdownItemHorizontalPadding = 12.0;

  /// Vertical padding for dropdown items
  static const double dropdownItemVerticalPadding = 8.0;

  // ============================================================================
  // ICON SIZES
  // ============================================================================

  /// Size of the main project icon when collapsed
  static const double collapsedIconSize = 24.0;

  /// Size of the main project icon when expanded
  static const double expandedIconSize = 28.0;

  /// Size of the dropdown arrow icon
  static const double dropdownArrowSize = 28.0;

  /// Size of the maximize/restore button icon
  static const double maximizeIconSize = 18.0;

  /// Size of project icons in the dropdown list
  static const double dropdownProjectIconSize = 20.0;

  /// Size of the active indicator dot
  static const double activeIndicatorSize = 6.0;

  // ============================================================================
  // BORDER & RADIUS
  // ============================================================================

  /// Border radius for the widget corners
  static const double borderRadius = 10.0;

  /// Border width around the widget
  static const double borderWidth = 1.0;

  /// Border width for the dropdown separator
  static const double dropdownBorderWidth = 1.0;

  // ============================================================================
  // ANIMATION
  // ============================================================================

  /// Duration for expand/collapse animations
  static const Duration animationDuration = Duration(
    milliseconds: 300,
  );

  // ============================================================================
  // SLIDE ANIMATION
  // ============================================================================

  /// Fixed widget width (always 280px)
  static const double fixedWidgetWidth = 280.0;

  /// Width of the visible "pill" area when collapsed (used for hit-testing)
  static const double collapsedVisibleWidth = 60.0;

  /// How much to offset the widget horizontally when slid out
  /// Widget slides right so only ~60px is visible
  static const double slideOutOffset =
      fixedWidgetWidth - collapsedVisibleWidth;

  /// How much to offset the widget horizontally when slid in (fully visible)
  static const double slideInOffset = 0.0;

  // ============================================================================
  // TYPOGRAPHY
  // ============================================================================

  /// Font size for project name text
  static const double projectNameFontSize = 14.0;

  /// Font size for timer text
  static const double timerFontSize = 14.0;

  /// Letter spacing for timer text
  static const double timerLetterSpacing = 1.5;

  /// Font size for dropdown project names
  static const double dropdownProjectFontSize = 14.0;

  /// Font size for dropdown project times
  static const double dropdownTimeFontSize = 12.0;

  /// Spacing between project name and timer
  static const double nameTimerSpacing = 2.0;

  // ============================================================================
  // OPACITY & SHADOW
  // ============================================================================

  /// Opacity for shadow color
  static const double shadowOpacity = 0.15;

  /// Shadow blur radius
  static const double shadowBlurRadius = 10.0;

  /// Shadow offset
  static const double shadowOffsetX = -2.0;
  static const double shadowOffsetY = 2.0;

  /// Border color opacity
  static const double borderColorOpacity = 0.2;

  /// Dropdown border color opacity
  static const double dropdownBorderOpacity = 0.2;

  // ============================================================================
  // OTHER
  // ============================================================================

  /// Padding for the maximize button
  static const double maximizeButtonPadding = 4.0;

  /// Margin for active indicator
  static const double activeIndicatorMargin = 8.0;
}
