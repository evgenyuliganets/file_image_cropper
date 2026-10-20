import 'package:flutter/widgets.dart';

/// Shapes available for the built-in crop drag handles.
enum CropHandleShape {
  /// Square drag handle.
  square,

  /// Circular drag handle.
  circle,
}

/// Visual configuration for the built-in crop mask, grid, and drag handles.
final class CropOverlayStyle {
  /// Creates visual configuration for the built-in crop overlay.
  const CropOverlayStyle({
    this.maskColor = const Color(0x99000000),
    this.borderColor = const Color(0xffffffff),
    this.borderWidth = 2,
    this.borderRadius = 0,
    this.gridColor = const Color(0x99ffffff),
    this.gridStrokeWidth = 1,
    this.gridRows = 3,
    this.gridColumns = 3,
    this.showGrid = true,
    this.handleColor = const Color(0xffffffff),
    this.handleSize = 12,
    this.handleHitSize = 48,
    this.handleShape = CropHandleShape.square,
  });

  /// Color drawn over the unselected image area.
  final Color maskColor;

  /// Selection border color.
  final Color borderColor;

  /// Selection border thickness.
  final double borderWidth;

  /// Selection border corner radius.
  final double borderRadius;

  /// Internal grid line color.
  final Color gridColor;

  /// Internal grid line thickness.
  final double gridStrokeWidth;

  /// Number of horizontal grid divisions.
  final int gridRows;

  /// Number of vertical grid divisions.
  final int gridColumns;

  /// Whether the internal composition grid is visible.
  final bool showGrid;

  /// Drag handle color.
  final Color handleColor;

  /// Visible drag handle size.
  final double handleSize;

  /// Touch target size around each handle.
  final double handleHitSize;

  /// Shape of the drag handles.
  final CropHandleShape handleShape;

  /// Returns a copy with selected values replaced.
  CropOverlayStyle copyWith({
    Color? maskColor,
    Color? borderColor,
    double? borderWidth,
    double? borderRadius,
    Color? gridColor,
    double? gridStrokeWidth,
    int? gridRows,
    int? gridColumns,
    bool? showGrid,
    Color? handleColor,
    double? handleSize,
    double? handleHitSize,
    CropHandleShape? handleShape,
  }) => CropOverlayStyle(
    maskColor: maskColor ?? this.maskColor,
    borderColor: borderColor ?? this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
    borderRadius: borderRadius ?? this.borderRadius,
    gridColor: gridColor ?? this.gridColor,
    gridStrokeWidth: gridStrokeWidth ?? this.gridStrokeWidth,
    gridRows: gridRows ?? this.gridRows,
    gridColumns: gridColumns ?? this.gridColumns,
    showGrid: showGrid ?? this.showGrid,
    handleColor: handleColor ?? this.handleColor,
    handleSize: handleSize ?? this.handleSize,
    handleHitSize: handleHitSize ?? this.handleHitSize,
    handleShape: handleShape ?? this.handleShape,
  );
}
