import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum PaperStyle {
  grid('Kareli', Icons.grid_on_rounded),
  lined('Çizgili', Icons.format_align_justify_rounded),
  dotted('Noktalı', Icons.blur_on_rounded),
  blank('Boş', Icons.crop_portrait_rounded);

  final String label;
  final IconData icon;
  const PaperStyle(this.label, this.icon);
}

enum PaperColorTheme {
  white('Standart Beyaz', 'Beyaz', Color(0xFFFFFFFF), Color(0xFF2B4D7E)),
  cream('Krem / Fildişi', 'Krem', Color(0xFFF9F5EB), Color(0xFF7C6F59)),
  black('Siyah Kağıt', 'Siyah', Color(0xFF1E2022), Color(0xFF94A3B8)),
  yellow('Pastel Sarı', 'Sarı', Color(0xFFFFFBEB), Color(0xFF92400E)),
  green('Pastel Yeşil', 'Yeşil', Color(0xFFF0FDF4), Color(0xFF047857)),
  gray('Gri Zemin', 'Gri', Color(0xFFE5E7EB), Color(0xFF94A3B8));

  final String label;
  final String shortLabel;
  final Color backgroundColor;
  final Color gridLineColor;

  const PaperColorTheme(
    this.label,
    this.shortLabel,
    this.backgroundColor,
    this.gridLineColor,
  );

  bool get isDark => backgroundColor.computeLuminance() < 0.2;
}

class PaperConfig {
  final PaperStyle style;
  final double spacing;
  final double opacity;
  final bool showSpineFold;
  final PaperColorTheme colorTheme;

  const PaperConfig({
    this.style = PaperStyle.grid,
    this.spacing = 32.0,
    this.opacity = 0.22,
    this.showSpineFold = true,
    this.colorTheme = PaperColorTheme.white,
  });

  PaperConfig copyWith({
    PaperStyle? style,
    double? spacing,
    double? opacity,
    bool? showSpineFold,
    PaperColorTheme? colorTheme,
  }) {
    return PaperConfig(
      style: style ?? this.style,
      spacing: spacing ?? this.spacing,
      opacity: opacity ?? this.opacity,
      showSpineFold: showSpineFold ?? this.showSpineFold,
      colorTheme: colorTheme ?? this.colorTheme,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'style': style.name,
      'spacing': spacing,
      'opacity': opacity,
      'showSpineFold': showSpineFold,
      'colorTheme': colorTheme.name,
    };
  }

  factory PaperConfig.fromMap(Map<String, dynamic> map) {
    return PaperConfig(
      style: PaperStyle.values.firstWhere(
        (e) => e.name == map['style'],
        orElse: () => PaperStyle.grid,
      ),
      spacing: (map['spacing'] as num?)?.toDouble() ?? 32.0,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.22,
      showSpineFold: map['showSpineFold'] as bool? ?? true,
      colorTheme: PaperColorTheme.values.firstWhere(
        (e) => e.name == map['colorTheme'],
        orElse: () => PaperColorTheme.white,
      ),
    );
  }
}

enum DrawingTool {
  pen('Tükenmez Kalem', Icons.edit_rounded, 2.5),
  fountain('Dolma Kalem', Icons.history_edu_rounded, 3.2),
  monoline('Monoline Kalem', Icons.draw_rounded, 1.8),
  pencil('Kurşun Kalem', Icons.mode_edit_outline_rounded, 2.0),
  marker('Fosforlu Kalem', Icons.highlight_rounded, 20.0),
  watercolor('Sulu Boya', Icons.brush_rounded, 24.0),
  crayon('Pastel Boya', Icons.grain_rounded, 14.0),
  tape('Ezber Bandı', Icons.view_agenda_rounded, 24.0),
  eraser('Silgi', Icons.auto_fix_normal_rounded, 22.0),
  lasso('Kement Seçim', Icons.gesture_rounded, 1.0),
  line('Düz Çizgi', Icons.horizontal_rule_rounded, 2.5),
  arrow('Ok Çizgisi', Icons.arrow_right_alt_rounded, 2.5),
  curve('Kavisli Çizgi', Icons.gesture_rounded, 2.5),
  angle('3 Noktalı Açı', Icons.polyline_rounded, 2.5),
  rectangle('Dikdörtgen', Icons.crop_square_rounded, 2.5),
  square('Kare', Icons.square_outlined, 2.5),
  circle('Daire', Icons.circle_outlined, 2.5),
  ellipse('Elips', Icons.egg_outlined, 2.5),
  triangle('Üçgen', Icons.change_history_rounded, 2.5),
  rightTriangle('Dik Üçgen', Icons.square_foot_rounded, 2.5),
  pentagon('Beşgen', Icons.pentagon_outlined, 2.5),
  hexagon('Altıgen', Icons.hexagon_outlined, 2.5),
  deltoid('Deltoid', Icons.diamond_outlined, 2.5),
  rectangleFilled('Dolu Dikdörtgen', Icons.rectangle_rounded, 2.5),
  squareFilled('Dolu Kare', Icons.square_rounded, 2.5),
  circleFilled('Dolu Daire', Icons.circle, 2.5),
  ellipseFilled('Dolu Elips', Icons.egg_rounded, 2.5),
  triangleFilled('Dolu Üçgen', Icons.change_history, 2.5),
  rightTriangleFilled('Dolu Dik Üçgen', Icons.square_foot_rounded, 2.5),
  pentagonFilled('Dolu Beşgen', Icons.pentagon_rounded, 2.5),
  hexagonFilled('Dolu Altıgen', Icons.hexagon_rounded, 2.5),
  deltoidFilled('Dolu Deltoid', Icons.diamond_rounded, 2.5),
  text('Metin', Icons.title_rounded, 1.0);

  final String label;
  final IconData icon;
  final double defaultWidth;
  const DrawingTool(this.label, this.icon, this.defaultWidth);

  bool get isShape =>
      this == DrawingTool.line ||
      this == DrawingTool.arrow ||
      this == DrawingTool.curve ||
      this == DrawingTool.rectangle ||
      this == DrawingTool.square ||
      this == DrawingTool.circle ||
      this == DrawingTool.ellipse ||
      this == DrawingTool.triangle ||
      this == DrawingTool.rightTriangle ||
      this == DrawingTool.pentagon ||
      this == DrawingTool.hexagon ||
      this == DrawingTool.deltoid ||
      this == DrawingTool.rectangleFilled ||
      this == DrawingTool.squareFilled ||
      this == DrawingTool.circleFilled ||
      this == DrawingTool.ellipseFilled ||
      this == DrawingTool.triangleFilled ||
      this == DrawingTool.rightTriangleFilled ||
      this == DrawingTool.pentagonFilled ||
      this == DrawingTool.hexagonFilled ||
      this == DrawingTool.deltoidFilled;

  bool get isFilled =>
      this == DrawingTool.rectangleFilled ||
      this == DrawingTool.squareFilled ||
      this == DrawingTool.circleFilled ||
      this == DrawingTool.ellipseFilled ||
      this == DrawingTool.triangleFilled ||
      this == DrawingTool.rightTriangleFilled ||
      this == DrawingTool.pentagonFilled ||
      this == DrawingTool.hexagonFilled ||
      this == DrawingTool.deltoidFilled;

  bool get isLineOrArrow =>
      this == DrawingTool.line ||
      this == DrawingTool.arrow ||
      this == DrawingTool.curve;
}

enum SelectionHandle {
  topLeft,
  topCenter,
  topRight,
  centerRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
  centerLeft,
  lineStart,
  lineEnd,
  lineVertex,
  lineControl,
}

enum LassoSelectionMode {
  rectangle(
    'Kare Seçim',
    Icons.crop_square_rounded,
    'Dikdörtgen veya kare alan seçimi',
  ),
  freeform(
    'Serbest Kement',
    Icons.gesture_rounded,
    'Serbest çizgi ile çevreleyerek seç',
  );

  final String label;
  final IconData icon;
  final String description;

  const LassoSelectionMode(this.label, this.icon, this.description);
}

enum EraserType {
  object(
    'Nesne Silgisi',
    Icons.auto_fix_normal_rounded,
    'Tüm çizgiyi tek dokunuşla siler',
  ),
  pixel(
    'Piksel Silgisi',
    Icons.crop_free_rounded,
    'Temas eden kısmı hassasça siler',
  );

  final String label;
  final IconData icon;
  final String description;

  const EraserType(this.label, this.icon, this.description);
}

enum QuickAccessSubPage {
  main,
  layers,
  groups,
  assets,
  photos,
  files,
  pdfViewer,
  pageSettings,
}

enum SmartGuideAlignmentType {
  edge,
  center,
  spacing,
}

class SmartAlignmentGuide {
  final bool isVertical; // true = vertical guideline (x is fixed), false = horizontal guideline (y is fixed)
  final double coordinate;
  final double start;
  final double end;
  final SmartGuideAlignmentType type;
  final Rect? secondarySpacingRect;
  final double? gapSize;

  const SmartAlignmentGuide({
    required this.isVertical,
    required this.coordinate,
    required this.start,
    required this.end,
    this.type = SmartGuideAlignmentType.edge,
    this.secondarySpacingRect,
    this.gapSize,
  });
}

class PdfPageDragData {
  final String fileId;
  final String fileName;
  final int pageIndex;
  final String? previewBase64;
  final double aspectRatio; // width / height

  const PdfPageDragData({
    required this.fileId,
    required this.fileName,
    required this.pageIndex,
    this.previewBase64,
    this.aspectRatio = 0.707,
  });
}

class EraserMask {
  final String id;
  final List<Offset> points;
  final double strokeWidth;

  const EraserMask({
    required this.id,
    required this.points,
    required this.strokeWidth,
  });

  EraserMask copyWith({
    String? id,
    List<Offset>? points,
    double? strokeWidth,
  }) {
    return EraserMask(
      id: id ?? this.id,
      points: points ?? this.points,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  EraserMask translate(Offset delta) {
    return EraserMask(
      id: id,
      points: points.map((p) => p + delta).toList(),
      strokeWidth: strokeWidth,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'points': points.map((p) => [p.dx, p.dy]).toList(),
      'strokeWidth': strokeWidth,
    };
  }

  factory EraserMask.fromMap(Map<String, dynamic> map) {
    final rawPoints = (map['points'] as List<dynamic>? ?? []);
    final points = rawPoints.map((pt) {
      final list = pt as List<dynamic>;
      return Offset(
        (list[0] as num).toDouble(),
        (list[1] as num).toDouble(),
      );
    }).toList();

    return EraserMask(
      id: map['id'] as String? ?? 'mask_${DateTime.now().microsecondsSinceEpoch}',
      points: points,
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 20.0,
    );
  }
}

class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final DrawingTool tool;
  final double rotation;
  final String? groupId;
  final bool isLocked;
  final int? layerOrder;
  final List<EraserMask> eraserMasks;
  final bool isTapeRevealed;

  const DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.tool,
    this.rotation = 0.0,
    this.groupId,
    this.isLocked = false,
    this.layerOrder,
    this.eraserMasks = const [],
    this.isTapeRevealed = false,
  });

  DrawingStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    DrawingTool? tool,
    double? rotation,
    String? groupId,
    bool clearGroupId = false,
    bool? isLocked,
    int? layerOrder,
    List<EraserMask>? eraserMasks,
    bool? isTapeRevealed,
  }) {
    return DrawingStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      tool: tool ?? this.tool,
      rotation: rotation ?? this.rotation,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      isLocked: isLocked ?? this.isLocked,
      layerOrder: layerOrder ?? this.layerOrder,
      eraserMasks: eraserMasks ?? this.eraserMasks,
      isTapeRevealed: isTapeRevealed ?? this.isTapeRevealed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => [p.dx, p.dy]).toList(),
      'color': color.toARGB32(),
      'strokeWidth': strokeWidth,
      'tool': tool.name,
      'rotation': rotation,
      if (groupId != null) 'groupId': groupId,
      if (isLocked) 'isLocked': true,
      if (layerOrder != null) 'layerOrder': layerOrder,
      if (eraserMasks.isNotEmpty)
        'eraserMasks': eraserMasks.map((m) => m.toMap()).toList(),
      if (isTapeRevealed) 'isTapeRevealed': true,
    };
  }

  factory DrawingStroke.fromMap(Map<String, dynamic> map) {
    final rawPoints = (map['points'] as List<dynamic>? ?? []);
    final points = rawPoints.map((pt) {
      final list = pt as List<dynamic>;
      return Offset(
        (list[0] as num).toDouble(),
        (list[1] as num).toDouble(),
      );
    }).toList();

    final rawMasks = (map['eraserMasks'] as List<dynamic>? ?? []);
    final eraserMasks = rawMasks
        .map((m) => EraserMask.fromMap(m as Map<String, dynamic>))
        .toList();

    return DrawingStroke(
      points: points,
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF000000),
      strokeWidth: (map['strokeWidth'] as num?)?.toDouble() ?? 2.5,
      tool: DrawingTool.values.firstWhere(
        (e) => e.name == map['tool'],
        orElse: () => DrawingTool.pen,
      ),
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      groupId: map['groupId'] as String?,
      isLocked: map['isLocked'] as bool? ?? false,
      layerOrder: (map['layerOrder'] as num?)?.toInt(),
      eraserMasks: eraserMasks,
      isTapeRevealed: map['isTapeRevealed'] as bool? ?? false,
    );
  }
}

class DayScheduleItem {
  final DateTime date;
  final String dayName;
  final String dayNameEnglish;
  final String text;

  const DayScheduleItem({
    required this.date,
    required this.dayName,
    required this.dayNameEnglish,
    this.text = '',
  });

  DayScheduleItem copyWith({String? text}) {
    return DayScheduleItem(
      date: date,
      dayName: dayName,
      dayNameEnglish: dayNameEnglish,
      text: text ?? this.text,
    );
  }
}

class DayCalendarEvent {
  static const List<int> palette = [
    0xFF0A84FF, // Apple Blue
    0xFF8B5CF6, // Violet
    0xFF10B981, // Emerald
    0xFFF97316, // Amber / Orange
    0xFFF43F5E, // Rose
  ];

  final String id;
  final String title;
  final bool isAllDay;
  final int startMinutes;
  final int endMinutes;
  final int colorValue;
  final String notes;

  const DayCalendarEvent({
    required this.id,
    required this.title,
    this.isAllDay = false,
    this.startMinutes = 540, // 09:00
    this.endMinutes = 600, // 10:00
    this.colorValue = 0xFF0A84FF,
    this.notes = '',
  });

  static String formatMinutes(int totalMinutes) {
    final clamped = totalMinutes.clamp(0, 1440);
    final h = (clamped ~/ 60) % 24;
    final m = clamped % 60;
    if (clamped == 1440) return '24:00';
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get formattedTimeRange {
    if (isAllDay) return 'Tam gün';
    return '${formatMinutes(startMinutes)} – ${formatMinutes(endMinutes)}';
  }

  DayCalendarEvent copyWith({
    String? id,
    String? title,
    bool? isAllDay,
    int? startMinutes,
    int? endMinutes,
    int? colorValue,
    String? notes,
  }) {
    return DayCalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      isAllDay: isAllDay ?? this.isAllDay,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      colorValue: colorValue ?? this.colorValue,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'isAllDay': isAllDay,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'colorValue': colorValue,
    'notes': notes,
  };

  factory DayCalendarEvent.fromMap(Map<String, dynamic> map) {
    final start = ((map['startMinutes'] as num?)?.toInt() ?? 540).clamp(0, 1410);
    final rawEnd = (map['endMinutes'] as num?)?.toInt() ?? (start + 60);
    final end = rawEnd.clamp(start + 15, 1440);
    return DayCalendarEvent(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      isAllDay: map['isAllDay'] as bool? ?? false,
      startMinutes: start,
      endMinutes: end,
      colorValue: (map['colorValue'] as num?)?.toInt() ?? 0xFF0A84FF,
      notes: map['notes'] as String? ?? '',
    );
  }
}

class PlannerTaskItem {
  final String id;
  final String title;
  final bool isCompleted;

  const PlannerTaskItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  PlannerTaskItem copyWith({String? id, String? title, bool? isCompleted}) {
    return PlannerTaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
  };

  factory PlannerTaskItem.fromMap(Map<String, dynamic> map) {
    return PlannerTaskItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      isCompleted: map['isCompleted'] as bool? ?? false,
    );
  }
}

enum CanvaTextPreset {
  heading('Başlık Ekle', 'Başlık', 26.0, true, null),
  subheading('Alt Başlık Ekle', 'Alt Başlık', 19.0, true, null),
  body('Metin Kutusu Ekle', 'Metin yazın...', 15.0, false, null),
  stickyNote('Not Kutusu (Post-it)', 'Notunuzu yazın...', 15.0, false, 0xFFFEF08A),
  bulletList('Madde Listesi Ekle', '• Birinci madde\n• İkinci madde', 15.0, false, null);

  final String label;
  final String defaultText;
  final double defaultFontSize;
  final bool defaultBold;
  final int? defaultBgColor;

  const CanvaTextPreset(
    this.label,
    this.defaultText,
    this.defaultFontSize,
    this.defaultBold,
    this.defaultBgColor,
  );
}

class CanvasTextItem {
  final String id;
  final Offset position;
  final String text;
  final Color color;
  final double fontSize;
  final String fontFamily;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String textAlign; // 'left' | 'center' | 'right'
  final int? backgroundColor;
  final double borderRadius;
  final double rotation;
  final double width;
  final bool isLocked;
  final int? layerOrder;
  final String? groupId;

  const CanvasTextItem({
    required this.id,
    required this.position,
    required this.text,
    this.color = const Color(0xFF1E293B),
    this.fontSize = 16.0,
    this.fontFamily = 'sans',
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.textAlign = 'left',
    this.backgroundColor,
    this.borderRadius = 0.0,
    this.rotation = 0.0,
    this.width = 220.0,
    this.isLocked = false,
    this.layerOrder,
    this.groupId,
  });

  CanvasTextItem copyWith({
    String? id,
    Offset? position,
    String? text,
    Color? color,
    double? fontSize,
    String? fontFamily,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    String? textAlign,
    int? backgroundColor,
    bool clearBackgroundColor = false,
    double? borderRadius,
    double? rotation,
    double? width,
    bool? isLocked,
    int? layerOrder,
    String? groupId,
    bool clearGroupId = false,
  }) {
    return CanvasTextItem(
      id: id ?? this.id,
      position: position ?? this.position,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      textAlign: textAlign ?? this.textAlign,
      backgroundColor:
          clearBackgroundColor ? null : (backgroundColor ?? this.backgroundColor),
      borderRadius: borderRadius ?? this.borderRadius,
      rotation: rotation ?? this.rotation,
      width: width ?? this.width,
      isLocked: isLocked ?? this.isLocked,
      layerOrder: layerOrder ?? this.layerOrder,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'isBold': isBold,
    'isItalic': isItalic,
    'isUnderline': isUnderline,
    'textAlign': textAlign,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    'borderRadius': borderRadius,
    'rotation': rotation,
    'width': width,
    'isLocked': isLocked,
    if (layerOrder != null) 'layerOrder': layerOrder,
    if (groupId != null) 'groupId': groupId,
  };

  factory CanvasTextItem.fromMap(Map<String, dynamic> map) {
    return CanvasTextItem(
      id: map['id'] as String? ?? '',
      position: Offset(
        (map['x'] as num?)?.toDouble() ?? 50.0,
        (map['y'] as num?)?.toDouble() ?? 50.0,
      ),
      text: map['text'] as String? ?? '',
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF1E293B),
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16.0,
      fontFamily: map['fontFamily'] as String? ?? 'sans',
      isBold: map['isBold'] as bool? ?? false,
      isItalic: map['isItalic'] as bool? ?? false,
      isUnderline: map['isUnderline'] as bool? ?? false,
      textAlign: map['textAlign'] as String? ?? 'left',
      backgroundColor: (map['backgroundColor'] as num?)?.toInt(),
      borderRadius: (map['borderRadius'] as num?)?.toDouble() ?? 0.0,
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      width: (map['width'] as num?)?.toDouble() ?? 220.0,
      isLocked: map['isLocked'] as bool? ?? false,
      layerOrder: (map['layerOrder'] as num?)?.toInt(),
      groupId: map['groupId'] as String?,
    );
  }
  double computeHeight() {
    final tp = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? ' ' : text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          height: 1.32,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (width - 24.0).clamp(10.0, 4000.0));
    final calculated = tp.height + 16.0;
    return calculated < 38.0 ? 38.0 : calculated;
  }
}

enum CanvasLayerType {
  stroke,
  text,
  image,
  paperRegion,
}

class CanvasLayerEntry {
  final CanvasLayerType type;
  final int? strokeIndex;
  final DrawingStroke? stroke;
  final String? textId;
  final CanvasTextItem? textItem;
  final String? imageId;
  final CanvasImageItem? imageItem;
  final String? paperRegionId;
  final CanvasPaperRegion? paperRegion;
  final int layerOrder;

  const CanvasLayerEntry.stroke({
    required int this.strokeIndex,
    required DrawingStroke this.stroke,
    required this.layerOrder,
  })  : type = CanvasLayerType.stroke,
        textId = null,
        textItem = null,
        imageId = null,
        imageItem = null,
        paperRegionId = null,
        paperRegion = null;

  const CanvasLayerEntry.text({
    required String this.textId,
    required CanvasTextItem this.textItem,
    required this.layerOrder,
  })  : type = CanvasLayerType.text,
        strokeIndex = null,
        stroke = null,
        imageId = null,
        imageItem = null,
        paperRegionId = null,
        paperRegion = null;

  const CanvasLayerEntry.image({
    required String this.imageId,
    required CanvasImageItem this.imageItem,
    required this.layerOrder,
  })  : type = CanvasLayerType.image,
        strokeIndex = null,
        stroke = null,
        textId = null,
        textItem = null,
        paperRegionId = null,
        paperRegion = null;

  const CanvasLayerEntry.paperRegion({
    required String this.paperRegionId,
    required CanvasPaperRegion this.paperRegion,
    required this.layerOrder,
  })  : type = CanvasLayerType.paperRegion,
        strokeIndex = null,
        stroke = null,
        textId = null,
        textItem = null,
        imageId = null,
        imageItem = null;

  bool get isStroke => type == CanvasLayerType.stroke;
  bool get isText => type == CanvasLayerType.text;
  bool get isImage => type == CanvasLayerType.image;
  bool get isPaperRegion => type == CanvasLayerType.paperRegion;
  String? get groupId {
    switch (type) {
      case CanvasLayerType.stroke:
        return stroke?.groupId;
      case CanvasLayerType.text:
        return textItem?.groupId;
      case CanvasLayerType.image:
        return imageItem?.groupId;
      case CanvasLayerType.paperRegion:
        return paperRegion?.groupId;
    }
  }
  bool get isLocked {
    switch (type) {
      case CanvasLayerType.stroke:
        return stroke?.isLocked ?? false;
      case CanvasLayerType.text:
        return textItem?.isLocked ?? false;
      case CanvasLayerType.image:
        return imageItem?.isLocked ?? false;
      case CanvasLayerType.paperRegion:
        return paperRegion?.isLocked ?? false;
    }
  }

  String get uniqueKey {
    switch (type) {
      case CanvasLayerType.stroke:
        return 'layer_stroke_$strokeIndex';
      case CanvasLayerType.text:
        return 'layer_text_$textId';
      case CanvasLayerType.image:
        return 'layer_image_$imageId';
      case CanvasLayerType.paperRegion:
        return 'layer_paper_region_$paperRegionId';
    }
  }

  CanvasLayerEntry withLayerOrder(int order) {
    switch (type) {
      case CanvasLayerType.stroke:
        return CanvasLayerEntry.stroke(
          strokeIndex: strokeIndex!,
          stroke: stroke!,
          layerOrder: order,
        );
      case CanvasLayerType.text:
        return CanvasLayerEntry.text(
          textId: textId!,
          textItem: textItem!,
          layerOrder: order,
        );
      case CanvasLayerType.image:
        return CanvasLayerEntry.image(
          imageId: imageId!,
          imageItem: imageItem!,
          layerOrder: order,
        );
      case CanvasLayerType.paperRegion:
        return CanvasLayerEntry.paperRegion(
          paperRegionId: paperRegionId!,
          paperRegion: paperRegion!,
          layerOrder: order,
        );
    }
  }
}

class CanvasImageItem {
  final String id;
  final Offset position;
  final double width;
  final double height;
  final String base64Data;
  final String? name;
  final bool isLocked;
  final double rotation;
  final int? layerOrder;
  final Uint8List? memoryBytes;
  final String? groupId;

  const CanvasImageItem({
    required this.id,
    required this.position,
    this.width = 220.0,
    this.height = 160.0,
    required this.base64Data,
    this.name,
    this.isLocked = false,
    this.rotation = 0.0,
    this.layerOrder,
    this.memoryBytes,
    this.groupId,
  });

  Rect get rect => Rect.fromLTWH(position.dx, position.dy, width, height);
  Offset get center => Offset(position.dx + width / 2.0, position.dy + height / 2.0);

  Uint8List? get bytes {
    if (memoryBytes != null) return memoryBytes;
    if (base64Data.isNotEmpty) {
      try {
        return base64Decode(base64Data);
      } catch (_) {}
    }
    return null;
  }

  CanvasImageItem copyWith({
    String? id,
    Offset? position,
    double? width,
    double? height,
    String? base64Data,
    String? name,
    bool? isLocked,
    double? rotation,
    int? layerOrder,
    Uint8List? memoryBytes,
    String? groupId,
    bool clearGroupId = false,
  }) {
    return CanvasImageItem(
      id: id ?? this.id,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      base64Data: base64Data ?? this.base64Data,
      name: name ?? this.name,
      isLocked: isLocked ?? this.isLocked,
      rotation: rotation ?? this.rotation,
      layerOrder: layerOrder ?? this.layerOrder,
      memoryBytes: memoryBytes ?? this.memoryBytes,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'width': width,
    'height': height,
    'base64Data': base64Data,
    'name': name,
    'isLocked': isLocked,
    'rotation': rotation,
    if (layerOrder != null) 'layerOrder': layerOrder,
    if (groupId != null) 'groupId': groupId,
  };

  factory CanvasImageItem.fromMap(Map<String, dynamic> map) {
    final b64 = map['base64Data'] as String? ?? '';
    Uint8List? decoded;
    if (b64.isNotEmpty) {
      try {
        decoded = base64Decode(b64);
      } catch (_) {}
    }
    return CanvasImageItem(
      id: map['id'] as String? ?? '',
      position: Offset(
        (map['x'] as num?)?.toDouble() ?? 80.0,
        (map['y'] as num?)?.toDouble() ?? 100.0,
      ),
      width: (map['width'] as num?)?.toDouble() ?? 220.0,
      height: (map['height'] as num?)?.toDouble() ?? 160.0,
      base64Data: b64,
      name: map['name'] as String?,
      isLocked: map['isLocked'] as bool? ?? false,
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      layerOrder: (map['layerOrder'] as num?)?.toInt(),
      memoryBytes: decoded,
      groupId: map['groupId'] as String?,
    );
  }
}

class CanvasFileItem {
  final String id;
  final Offset position;
  final String name;
  final int sizeBytes;
  final String? extension;
  final String? path;
  final String? base64Data;
  final bool isLocked;

  const CanvasFileItem({
    required this.id,
    required this.position,
    required this.name,
    this.sizeBytes = 0,
    this.extension,
    this.path,
    this.base64Data,
    this.isLocked = false,
  });

  CanvasFileItem copyWith({
    String? id,
    Offset? position,
    String? name,
    int? sizeBytes,
    String? extension,
    String? path,
    String? base64Data,
    bool? isLocked,
  }) {
    return CanvasFileItem(
      id: id ?? this.id,
      position: position ?? this.position,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      extension: extension ?? this.extension,
      path: path ?? this.path,
      base64Data: base64Data ?? this.base64Data,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'name': name,
    'sizeBytes': sizeBytes,
    'extension': extension,
    'path': path,
    'base64Data': base64Data,
    'isLocked': isLocked,
  };

  factory CanvasFileItem.fromMap(Map<String, dynamic> map) {
    return CanvasFileItem(
      id: map['id'] as String? ?? '',
      position: Offset(
        (map['x'] as num?)?.toDouble() ?? 80.0,
        (map['y'] as num?)?.toDouble() ?? 100.0,
      ),
      name: map['name'] as String? ?? 'Dosya',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      extension: map['extension'] as String?,
      path: map['path'] as String?,
      base64Data: map['base64Data'] as String?,
      isLocked: map['isLocked'] as bool? ?? false,
    );
  }
}

class CanvasPaperRegion {
  final String id;
  final Rect rect;
  final PaperStyle style;
  final double spacing;
  final double opacity;
  final double strokeWidth;
  final bool isLocked;
  final int? layerOrder;
  final String? groupId;
  final PaperColorTheme? colorTheme;
  final Color? customBackgroundColor;
  final Color? customGridLineColor;

  const CanvasPaperRegion({
    required this.id,
    required this.rect,
    required this.style,
    this.spacing = 24.0,
    this.opacity = 0.16,
    this.strokeWidth = 0.75,
    this.isLocked = false,
    this.layerOrder,
    this.groupId,
    this.colorTheme,
    this.customBackgroundColor,
    this.customGridLineColor,
  });

  CanvasPaperRegion copyWith({
    String? id,
    Rect? rect,
    PaperStyle? style,
    double? spacing,
    double? opacity,
    double? strokeWidth,
    bool? isLocked,
    int? layerOrder,
    String? groupId,
    bool clearGroupId = false,
    PaperColorTheme? colorTheme,
    Color? customBackgroundColor,
    Color? customGridLineColor,
    bool clearCustomColor = false,
    bool clearCustomGridColor = false,
  }) {
    return CanvasPaperRegion(
      id: id ?? this.id,
      rect: rect ?? this.rect,
      style: style ?? this.style,
      spacing: spacing ?? this.spacing,
      opacity: opacity ?? this.opacity,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isLocked: isLocked ?? this.isLocked,
      layerOrder: layerOrder ?? this.layerOrder,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      colorTheme: colorTheme ?? this.colorTheme,
      customBackgroundColor: clearCustomColor
          ? null
          : (customBackgroundColor ?? this.customBackgroundColor),
      customGridLineColor: clearCustomGridColor
          ? null
          : (customGridLineColor ?? this.customGridLineColor),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
    'style': style.name,
    'spacing': spacing,
    'opacity': opacity,
    'strokeWidth': strokeWidth,
    'isLocked': isLocked,
    if (layerOrder != null) 'layerOrder': layerOrder,
    if (groupId != null) 'groupId': groupId,
    if (colorTheme != null) 'colorTheme': colorTheme!.name,
    if (customBackgroundColor != null)
      'customBackgroundColor': customBackgroundColor!.toARGB32(),
    if (customGridLineColor != null)
      'customGridLineColor': customGridLineColor!.toARGB32(),
  };

  factory CanvasPaperRegion.fromMap(Map<String, dynamic> map) {
    final x = (map['x'] as num?)?.toDouble() ?? 50.0;
    final y = (map['y'] as num?)?.toDouble() ?? 50.0;
    final w = (map['w'] as num?)?.toDouble() ?? 250.0;
    final h = (map['h'] as num?)?.toDouble() ?? 200.0;
    final styleName = map['style'] as String? ?? 'grid';
    final style = PaperStyle.values.firstWhere(
      (s) => s.name == styleName,
      orElse: () => PaperStyle.grid,
    );
    final themeName = map['colorTheme'] as String?;
    final colorTheme = themeName != null
        ? PaperColorTheme.values.firstWhere(
            (t) => t.name == themeName,
            orElse: () => PaperColorTheme.white,
          )
        : null;
    final customBgInt = map['customBackgroundColor'] as int?;
    final customLineInt = map['customGridLineColor'] as int?;
    final strokeWidth = (map['strokeWidth'] as num?)?.toDouble() ?? 0.75;

    return CanvasPaperRegion(
      id: map['id'] as String? ?? '',
      rect: Rect.fromLTWH(x, y, w, h),
      style: style,
      spacing: (map['spacing'] as num?)?.toDouble() ?? 24.0,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.16,
      strokeWidth: strokeWidth,
      isLocked: map['isLocked'] as bool? ?? false,
      layerOrder: (map['layerOrder'] as num?)?.toInt(),
      groupId: map['groupId'] as String?,
      colorTheme: colorTheme,
      customBackgroundColor: customBgInt != null ? Color(customBgInt) : null,
      customGridLineColor: customLineInt != null ? Color(customLineInt) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasPaperRegion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          rect == other.rect &&
          style == other.style &&
          spacing == other.spacing &&
          opacity == other.opacity &&
          isLocked == other.isLocked &&
          layerOrder == other.layerOrder &&
          groupId == other.groupId;

  @override
  int get hashCode => Object.hash(id, rect, style, spacing, opacity, isLocked, layerOrder, groupId);
}

class SavedCanvasAsset {
  final String id;
  final String title;
  final List<DrawingStroke> strokes;
  final List<CanvasTextItem> texts;
  final DateTime createdAt;

  const SavedCanvasAsset({
    required this.id,
    required this.title,
    required this.strokes,
    this.texts = const [],
    required this.createdAt,
  });

  SavedCanvasAsset copyWith({
    String? id,
    String? title,
    List<DrawingStroke>? strokes,
    List<CanvasTextItem>? texts,
    DateTime? createdAt,
  }) {
    return SavedCanvasAsset(
      id: id ?? this.id,
      title: title ?? this.title,
      strokes: strokes ?? this.strokes,
      texts: texts ?? this.texts,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'strokes': strokes.map((s) => s.toMap()).toList(),
    if (texts.isNotEmpty) 'texts': texts.map((t) => t.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedCanvasAsset.fromMap(Map<String, dynamic> map) {
    final rawStrokes = map['strokes'] as List<dynamic>? ?? const [];
    final rawTexts = map['texts'] as List<dynamic>? ?? const [];
    return SavedCanvasAsset(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Varlık',
      strokes: rawStrokes
          .map((e) => DrawingStroke.fromMap(e as Map<String, dynamic>))
          .toList(),
      texts: rawTexts
          .map((e) => CanvasTextItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class NoteSubject {
  final String id;
  final String name;
  final Color color;
  final DateTime createdAt;

  const NoteSubject({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  NoteSubject copyWith({
    String? id,
    String? name,
    Color? color,
    DateTime? createdAt,
  }) {
    return NoteSubject(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory NoteSubject.fromMap(Map<String, dynamic> map) {
    return NoteSubject(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Konu',
      color: Color((map['color'] as num?)?.toInt() ?? 0xFF2563EB),
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class NoteDocument {
  final String id;
  final String title;
  final String subjectId;
  final PaperStyle paperStyle;
  final PaperColorTheme colorTheme;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int pageCount;

  const NoteDocument({
    required this.id,
    required this.title,
    required this.subjectId,
    this.paperStyle = PaperStyle.dotted,
    this.colorTheme = PaperColorTheme.white,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount = 1,
  });

  NoteDocument copyWith({
    String? id,
    String? title,
    String? subjectId,
    PaperStyle? paperStyle,
    PaperColorTheme? colorTheme,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? pageCount,
  }) {
    return NoteDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      subjectId: subjectId ?? this.subjectId,
      paperStyle: paperStyle ?? this.paperStyle,
      colorTheme: colorTheme ?? this.colorTheme,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subjectId': subjectId,
    'paperStyle': paperStyle.name,
    'colorTheme': colorTheme.name,
    'isFavorite': isFavorite,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'pageCount': pageCount,
  };

  factory NoteDocument.fromMap(Map<String, dynamic> map) {
    final styleStr = map['paperStyle'] as String?;
    final themeStr = map['colorTheme'] as String?;
    return NoteDocument(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Başlıksız Not',
      subjectId: map['subjectId'] as String? ?? 'general',
      paperStyle: PaperStyle.values.firstWhere(
        (e) => e.name == styleStr,
        orElse: () => PaperStyle.dotted,
      ),
      colorTheme: PaperColorTheme.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => PaperColorTheme.white,
      ),
      isFavorite: map['isFavorite'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      pageCount: (map['pageCount'] as num?)?.toInt() ?? 1,
    );
  }
}



