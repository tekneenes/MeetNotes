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

class PaperConfig {
  final PaperStyle style;
  final double spacing;
  final double opacity;
  final bool showSpineFold;

  const PaperConfig({
    this.style = PaperStyle.grid,
    this.spacing = 32.0,
    this.opacity = 0.22,
    this.showSpineFold = true,
  });

  PaperConfig copyWith({
    PaperStyle? style,
    double? spacing,
    double? opacity,
    bool? showSpineFold,
  }) {
    return PaperConfig(
      style: style ?? this.style,
      spacing: spacing ?? this.spacing,
      opacity: opacity ?? this.opacity,
      showSpineFold: showSpineFold ?? this.showSpineFold,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'style': style.name,
      'spacing': spacing,
      'opacity': opacity,
      'showSpineFold': showSpineFold,
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
  eraser('Silgi', Icons.auto_fix_normal_rounded, 22.0),
  lasso('Kement Seçim', Icons.gesture_rounded, 1.0),
  rectangle('Dikdörtgen', Icons.crop_square_rounded, 2.5),
  square('Kare', Icons.square_outlined, 2.5),
  circle('Daire', Icons.circle_outlined, 2.5),
  ellipse('Elips', Icons.egg_outlined, 2.5),
  triangle('Üçgen', Icons.change_history_rounded, 2.5),
  pentagon('Beşgen', Icons.pentagon_outlined, 2.5),
  hexagon('Altıgen', Icons.hexagon_outlined, 2.5),
  deltoid('Deltoid', Icons.diamond_outlined, 2.5),
  text('Metin', Icons.title_rounded, 1.0);

  final String label;
  final IconData icon;
  final double defaultWidth;
  const DrawingTool(this.label, this.icon, this.defaultWidth);

  bool get isShape =>
      this == DrawingTool.rectangle ||
      this == DrawingTool.square ||
      this == DrawingTool.circle ||
      this == DrawingTool.ellipse ||
      this == DrawingTool.triangle ||
      this == DrawingTool.pentagon ||
      this == DrawingTool.hexagon ||
      this == DrawingTool.deltoid;
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
}

enum QuickAccessSubPage {
  main,
  layers,
  groups,
}

class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final DrawingTool tool;
  final double rotation;
  final String? groupId;

  const DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.tool,
    this.rotation = 0.0,
    this.groupId,
  });

  DrawingStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    DrawingTool? tool,
    double? rotation,
    String? groupId,
    bool clearGroupId = false,
  }) {
    return DrawingStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      tool: tool ?? this.tool,
      rotation: rotation ?? this.rotation,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
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

class CanvasTextItem {
  final String id;
  final Offset position;
  final String text;
  final Color color;
  final double fontSize;

  const CanvasTextItem({
    required this.id,
    required this.position,
    required this.text,
    this.color = const Color(0xFF1E293B),
    this.fontSize = 15.0,
  });

  CanvasTextItem copyWith({
    String? id,
    Offset? position,
    String? text,
    Color? color,
    double? fontSize,
  }) {
    return CanvasTextItem(
      id: id ?? this.id,
      position: position ?? this.position,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
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
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 15.0,
    );
  }
}

class CanvasImageItem {
  final String id;
  final Offset position;
  final double width;
  final double height;
  final String base64Data;

  const CanvasImageItem({
    required this.id,
    required this.position,
    this.width = 220.0,
    this.height = 160.0,
    required this.base64Data,
  });

  CanvasImageItem copyWith({
    String? id,
    Offset? position,
    double? width,
    double? height,
    String? base64Data,
  }) {
    return CanvasImageItem(
      id: id ?? this.id,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      base64Data: base64Data ?? this.base64Data,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'width': width,
    'height': height,
    'base64Data': base64Data,
  };

  factory CanvasImageItem.fromMap(Map<String, dynamic> map) {
    return CanvasImageItem(
      id: map['id'] as String? ?? '',
      position: Offset(
        (map['x'] as num?)?.toDouble() ?? 80.0,
        (map['y'] as num?)?.toDouble() ?? 100.0,
      ),
      width: (map['width'] as num?)?.toDouble() ?? 220.0,
      height: (map['height'] as num?)?.toDouble() ?? 160.0,
      base64Data: map['base64Data'] as String? ?? '',
    );
  }
}


