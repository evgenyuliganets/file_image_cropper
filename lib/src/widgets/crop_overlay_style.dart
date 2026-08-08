import 'package:flutter/widgets.dart';

enum CropHandleShape { square, circle }

/// Visual configuration for the built-in crop mask, grid, and drag handles.
final class CropOverlayStyle {
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
    this.handleHitSize = 40,
    this.handleShape = CropHandleShape.square,
  });

  final Color maskColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final Color gridColor;
  final double gridStrokeWidth;
  final int gridRows;
  final int gridColumns;
  final bool showGrid;
  final Color handleColor;
  final double handleSize;
  final double handleHitSize;
  final CropHandleShape handleShape;

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
