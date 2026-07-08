import 'dart:convert';

enum TrackType { mainVideo, overlayPip, audio, text, sticker }

enum EditorAspectRatio {
  ratio9to16('9:16', 9 / 16),
  ratio16to9('16:9', 16 / 9),
  ratio1to1('1:1', 1.0),
  ratio4to5('4:5', 4 / 5);

  final String name;
  final double value;
  const EditorAspectRatio(this.name, this.value);
}

class Project {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  EditorAspectRatio aspectRatio;
  String? thumbnailPath;
  final List<Track> tracks;
  bool isProtected;
  String? protectionPassword;
  DateTime? protectionExpiry;

  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.aspectRatio,
    this.thumbnailPath,
    required this.tracks,
    this.isProtected = false,
    this.protectionPassword,
    this.protectionExpiry,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'aspectRatio': aspectRatio.name,
        'thumbnailPath': thumbnailPath,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'isProtected': isProtected,
        'protectionPassword': protectionPassword,
        'protectionExpiry': protectionExpiry?.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      aspectRatio: EditorAspectRatio.values.firstWhere(
        (e) => e.name == json['aspectRatio'],
        orElse: () => EditorAspectRatio.ratio9to16,
      ),
      thumbnailPath: json['thumbnailPath'] as String?,
      tracks: (json['tracks'] as List<dynamic>)
          .map((t) => Track.fromJson(t as Map<String, dynamic>))
          .toList(),
      isProtected: json['isProtected'] as bool? ?? false,
      protectionPassword: json['protectionPassword'] as String?,
      protectionExpiry: json['protectionExpiry'] != null
          ? DateTime.parse(json['protectionExpiry'] as String)
          : null,
    );
  }

  Project copy() {
    return Project.fromJson(jsonDecode(jsonEncode(toJson())));
  }
}

class Track {
  final String id;
  final TrackType type;
  final int zOrder;
  final List<TimelineClip> clips;

  Track({
    required this.id,
    required this.type,
    required this.zOrder,
    required this.clips,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'zOrder': zOrder,
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      type: TrackType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TrackType.mainVideo,
      ),
      zOrder: json['zOrder'] as int,
      clips: (json['clips'] as List<dynamic>)
          .map((c) => TimelineClip.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TimelineClip {
  final String id;
  final String? sourcePath; // null for text or stickers
  int startInTimelineMs;
  int durationMs;
  int startInSourceMs;
  double speed;
  double volume;
  final ClipTransform transform;
  final List<VideoEffect> effects;
  String? textContent; // For text overlays
  String? transitionType; // e.g. 'none', 'fade', 'zoom', 'slide'
  final List<int> beats; // Beat markers
  final List<ClipKeyframe> keyframes;
  String maskType; // 'none', 'linear', 'circle', 'rectangle', 'mirror'
  double maskSize; // 0.0 to 1.0 (controlling size or position)
  double maskFeather; // 0.0 to 1.0 (edge softness)
  String blendMode; // 'normal', 'multiply', 'screen', 'overlay', 'darken', 'lighten'
  String? chromaKeyColor; // e.g., '#00ff00' (null if inactive)
  double chromaKeyTolerance; // 0.0 to 1.0
  double chromaKeySpill; // 0.0 to 1.0

  // AI Tools Configurations (Phase 7)
  bool isAiBackgroundRemoved;
  bool isAiEnhanced;
  String? voiceEffect; // 'none', 'chipmunk', 'deep', 'robot', 'echo'
  bool isAiDenoised;

  TimelineClip({
    required this.id,
    this.sourcePath,
    required this.startInTimelineMs,
    required this.durationMs,
    required this.startInSourceMs,
    this.speed = 1.0,
    this.volume = 1.0,
    required this.transform,
    required this.effects,
    this.textContent,
    this.transitionType = 'none',
    List<int>? beats,
    List<ClipKeyframe>? keyframes,
    this.maskType = 'none',
    this.maskSize = 0.5,
    this.maskFeather = 0.1,
    this.blendMode = 'normal',
    this.chromaKeyColor,
    this.chromaKeyTolerance = 0.15,
    this.chromaKeySpill = 0.1,
    this.isAiBackgroundRemoved = false,
    this.isAiEnhanced = false,
    this.voiceEffect = 'none',
    this.isAiDenoised = false,
  })  : this.beats = beats ?? [],
        this.keyframes = keyframes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'startInTimelineMs': startInTimelineMs,
        'durationMs': durationMs,
        'startInSourceMs': startInSourceMs,
        'speed': speed,
        'volume': volume,
        'transform': transform.toJson(),
        'effects': effects.map((e) => e.toJson()).toList(),
        'textContent': textContent,
        'transitionType': transitionType,
        'beats': beats,
        'keyframes': keyframes.map((k) => k.toJson()).toList(),
        'maskType': maskType,
        'maskSize': maskSize,
        'maskFeather': maskFeather,
        'blendMode': blendMode,
        'chromaKeyColor': chromaKeyColor,
        'chromaKeyTolerance': chromaKeyTolerance,
        'chromaKeySpill': chromaKeySpill,
        'isAiBackgroundRemoved': isAiBackgroundRemoved,
        'isAiEnhanced': isAiEnhanced,
        'voiceEffect': voiceEffect,
        'isAiDenoised': isAiDenoised,
      };

  factory TimelineClip.fromJson(Map<String, dynamic> json) {
    return TimelineClip(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String?,
      startInTimelineMs: json['startInTimelineMs'] as int,
      durationMs: json['durationMs'] as int,
      startInSourceMs: json['startInSourceMs'] as int,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      transform: ClipTransform.fromJson(json['transform'] as Map<String, dynamic>),
      effects: (json['effects'] as List<dynamic>?)
              ?.map((e) => VideoEffect.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      textContent: json['textContent'] as String?,
      transitionType: json['transitionType'] as String? ?? 'none',
      beats: (json['beats'] as List<dynamic>?)?.map((b) => b as int).toList() ?? [],
      keyframes: (json['keyframes'] as List<dynamic>?)
              ?.map((k) => ClipKeyframe.fromJson(k as Map<String, dynamic>))
              .toList() ??
          [],
      maskType: json['maskType'] as String? ?? 'none',
      maskSize: (json['maskSize'] as num?)?.toDouble() ?? 0.5,
      maskFeather: (json['maskFeather'] as num?)?.toDouble() ?? 0.1,
      blendMode: json['blendMode'] as String? ?? 'normal',
      chromaKeyColor: json['chromaKeyColor'] as String?,
      chromaKeyTolerance: (json['chromaKeyTolerance'] as num?)?.toDouble() ?? 0.15,
      chromaKeySpill: (json['chromaKeySpill'] as num?)?.toDouble() ?? 0.1,
      isAiBackgroundRemoved: json['isAiBackgroundRemoved'] as bool? ?? false,
      isAiEnhanced: json['isAiEnhanced'] as bool? ?? false,
      voiceEffect: json['voiceEffect'] as String? ?? 'none',
      isAiDenoised: json['isAiDenoised'] as bool? ?? false,
    );
  }
}

class ClipTransform {
  double x;
  double y;
  double scale;
  double rotation;
  double opacity;

  ClipTransform({
    this.x = 0.0,
    this.y = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory ClipTransform.fromJson(Map<String, dynamic> json) {
    return ClipTransform(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

abstract class VideoEffect {
  String get id;
  String get type;
  Map<String, dynamic> toJson();

  static VideoEffect fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    if (type == 'color_adjust') {
      return AdjustmentEffect.fromJson(json);
    }
    if (type == 'lut_filter') {
      return FilterEffect.fromJson(json);
    }
    throw Exception('Unknown effect type: $type');
  }
}

class AdjustmentEffect implements VideoEffect {
  @override
  final String id;
  @override
  String get type => 'color_adjust';

  double brightness;
  double contrast;
  double saturation;

  AdjustmentEffect({
    required this.id,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
      };

  factory AdjustmentEffect.fromJson(Map<String, dynamic> json) {
    return AdjustmentEffect(
      id: json['id'] as String,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class FilterEffect implements VideoEffect {
  @override
  final String id;
  @override
  String get type => 'lut_filter';

  String filterName; // 'none', 'sepia', 'grayscale', 'vintage', 'cool', 'warm'

  FilterEffect({
    required this.id,
    required this.filterName,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'filterName': filterName,
      };

  factory FilterEffect.fromJson(Map<String, dynamic> json) {
    return FilterEffect(
      id: json['id'] as String,
      filterName: json['filterName'] as String,
    );
  }
}

class ClipKeyframe {
  final int timeOffsetMs; // offset from start of clip in ms
  double x;
  double y;
  double scale;
  double rotation;
  double opacity;

  ClipKeyframe({
    required this.timeOffsetMs,
    this.x = 0.0,
    this.y = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'timeOffsetMs': timeOffsetMs,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory ClipKeyframe.fromJson(Map<String, dynamic> json) {
    return ClipKeyframe(
      timeOffsetMs: json['timeOffsetMs'] as int,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
