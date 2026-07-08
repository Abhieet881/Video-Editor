import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import '../models/video_editor_models.dart';
import '../services/project_manager.dart';
import '../services/history_manager.dart';

class EditorScreen extends StatefulWidget {
  final Project project;
  const EditorScreen({super.key, required this.project});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late Project _project;
  final ProjectManager _projectManager = ProjectManager();
  final HistoryManager _historyManager = HistoryManager();

  VideoPlayerController? _previewController;
  TimelineClip? _currentPlayingClip;
  bool _isPlaying = false;
  int _currentTimeMs = 0; // Current playhead time in ms
  double _zoomScale = 1.0; // Timeline scale factor (pixels per millisecond)

  // Selection states
  TimelineClip? _selectedClip;
  Track? _selectedTrack;

  // Active toolbar panel mode: 'none', 'speed', 'volume', 'filters', 'adjust', 'transitions', 'text', 'stickers', 'audio', 'voiceover', 'tts', 'keyframes', 'mask', 'blend', 'chroma', 'ai'
  String _activePanel = 'none';

  // Audio recording controller
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordingDurationSec = 0;
  String? _recordedFilePath;

  // Speech to text controller
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _recognizedText = '';

  // Text to speech controller
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _ttsController = TextEditingController();

  // Secondary audio player controllers for playback sync
  final Map<String, VideoPlayerController> _audioTrackControllers = {};

  @override
  void initState() {
    super.initState();
    _project = widget.project.copy();
    _historyManager.pushState(_project);
    _initializeVideoPlayer();
    _initSpeechRecognizer();
    _initTTS();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    _audioRecorder.dispose();
    _ttsController.dispose();
    for (var controller in _audioTrackControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) => debugPrint('STT Error: $val'),
        onStatus: (val) => debugPrint('STT Status: $val'),
      );
      setState(() {});
    } catch (e) {
      debugPrint("Speech recognizer initialization failed: $e");
    }
  }

  Future<void> _initTTS() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint("TTS initialization failed: $e");
    }
  }

  // Initialize preview player for current active clip
  Future<void> _initializeVideoPlayer() async {
    final mainTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.mainVideo,
      orElse: () => Track(id: '', type: TrackType.mainVideo, zOrder: 0, clips: []),
    );

    if (mainTrack.clips.isEmpty) return;

    // Find the clip at the current playhead time
    TimelineClip? activeClip;
    for (var clip in mainTrack.clips) {
      if (_currentTimeMs >= clip.startInTimelineMs &&
          _currentTimeMs < clip.startInTimelineMs + clip.durationMs) {
        activeClip = clip;
        break;
      }
    }
    activeClip ??= mainTrack.clips.first;

    if (_currentPlayingClip?.id == activeClip.id && _previewController != null) {
      return;
    }

    _currentPlayingClip = activeClip;

    if (_previewController != null) {
      await _previewController!.dispose();
      _previewController = null;
    }

    if (activeClip.sourcePath != null) {
      final file = File(activeClip.sourcePath!);
      if (await file.exists()) {
        _previewController = VideoPlayerController.file(file);
        try {
          await _previewController!.initialize();
          final clipRelativeTime = _currentTimeMs - activeClip.startInTimelineMs;
          final sourceSeekTime = activeClip.startInSourceMs + clipRelativeTime;
          await _previewController!.seekTo(Duration(milliseconds: sourceSeekTime));
          
          _previewController!.addListener(_onVideoPlayerUpdate);
          
          if (_isPlaying) {
            _previewController!.play();
            _playAllActiveAudioClips();
          }
          setState(() {});
        } catch (e) {
          debugPrint("Failed to initialize video player: $e");
        }
      }
    }
  }

  void _onVideoPlayerUpdate() {
    if (!mounted || _previewController == null) return;

    final clip = _currentPlayingClip;
    if (clip != null && _isPlaying) {
      final controllerPos = _previewController!.value.position.inMilliseconds;
      final relativePos = controllerPos - clip.startInSourceMs;
      
      setState(() {
        _currentTimeMs = clip.startInTimelineMs + relativePos;
      });

      _syncAudioControllers();

      // If clip ends, transition to next clip or stop
      if (_currentTimeMs >= clip.startInTimelineMs + clip.durationMs) {
        _isPlaying = false;
        _previewController?.pause();
        _pauseAllActiveAudioClips();
        _currentTimeMs = clip.startInTimelineMs + clip.durationMs;
        _initializeVideoPlayer();
      }
    }
  }

  void _togglePlayPause() {
    if (_previewController == null) return;
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _previewController!.play();
        _playAllActiveAudioClips();
      } else {
        _previewController!.pause();
        _pauseAllActiveAudioClips();
      }
    });
  }

  void _seekTo(int timeMs) {
    int totalDuration = _calculateTotalDuration();
    final targetTime = timeMs.clamp(0, totalDuration);

    setState(() {
      _currentTimeMs = targetTime;
    });

    _initializeVideoPlayer().then((_) {
      if (_previewController != null && _currentPlayingClip != null) {
        final relativeTime = _currentTimeMs - _currentPlayingClip!.startInTimelineMs;
        final sourceSeekTime = _currentPlayingClip!.startInSourceMs + relativeTime;
        _previewController!.seekTo(Duration(milliseconds: sourceSeekTime));
      }
      _syncAudioControllers();
    });
  }

  void _playAllActiveAudioClips() {
    final audioTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () => Track(id: '', type: TrackType.audio, zOrder: -1, clips: []),
    );

    for (var clip in audioTrack.clips) {
      if (_currentTimeMs >= clip.startInTimelineMs &&
          _currentTimeMs < clip.startInTimelineMs + clip.durationMs &&
          clip.sourcePath != null) {
        
        final controller = _getOrCreateAudioController(clip);
        if (controller != null && controller.value.isInitialized) {
          final clipRelative = _currentTimeMs - clip.startInTimelineMs;
          controller.seekTo(Duration(milliseconds: clip.startInSourceMs + clipRelative));
          controller.setVolume(clip.volume);
          controller.play();
        }
      }
    }
  }

  void _pauseAllActiveAudioClips() {
    for (var controller in _audioTrackControllers.values) {
      controller.pause();
    }
  }

  void _syncAudioControllers() {
    final audioTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () => Track(id: '', type: TrackType.audio, zOrder: -1, clips: []),
    );

    for (var clip in audioTrack.clips) {
      final isInside = _currentTimeMs >= clip.startInTimelineMs &&
          _currentTimeMs < clip.startInTimelineMs + clip.durationMs;

      if (isInside && clip.sourcePath != null) {
        final controller = _getOrCreateAudioController(clip);
        if (controller != null && controller.value.isInitialized) {
          final clipRelative = _currentTimeMs - clip.startInTimelineMs;
          final targetSeek = Duration(milliseconds: clip.startInSourceMs + clipRelative);
          
          final drift = (controller.value.position - targetSeek).inMilliseconds.abs();
          if (drift > 150) {
            controller.seekTo(targetSeek);
          }

          if (_isPlaying && !controller.value.isPlaying) {
            controller.setVolume(clip.volume);
            controller.play();
          }
        }
      } else {
        final controller = _audioTrackControllers[clip.id];
        if (controller != null && controller.value.isPlaying) {
          controller.pause();
        }
      }
    }
  }

  VideoPlayerController? _getOrCreateAudioController(TimelineClip clip) {
    if (clip.sourcePath == null) return null;
    if (_audioTrackControllers.containsKey(clip.id)) {
      return _audioTrackControllers[clip.id];
    }

    final file = File(clip.sourcePath!);
    if (file.existsSync()) {
      final controller = VideoPlayerController.file(file);
      _audioTrackControllers[clip.id] = controller;
      controller.initialize().then((_) {
        if (mounted) setState(() {});
      });
      return controller;
    }
    return null;
  }

  int _calculateTotalDuration() {
    int maxDuration = 0;
    for (var track in _project.tracks) {
      for (var clip in track.clips) {
        final end = clip.startInTimelineMs + clip.durationMs;
        if (end > maxDuration) maxDuration = end;
      }
    }
    return maxDuration > 0 ? maxDuration : 5000;
  }

  void _saveProjectState() {
    _projectManager.saveProject(_project);
  }

  void _pushHistoryState() {
    _historyManager.pushState(_project);
    _saveProjectState();
    setState(() {});
  }

  void _undo() {
    final prev = _historyManager.undo(_project);
    if (prev != null) {
      setState(() {
        _project = prev;
        _currentTimeMs = 0;
        _selectedClip = null;
        _selectedTrack = null;
        _activePanel = 'none';
      });
      _initializeVideoPlayer();
      _saveProjectState();
    }
  }

  void _redo() {
    final next = _historyManager.redo(_project);
    if (next != null) {
      setState(() {
        _project = next;
        _currentTimeMs = 0;
        _selectedClip = null;
        _selectedTrack = null;
        _activePanel = 'none';
      });
      _initializeVideoPlayer();
      _saveProjectState();
    }
  }

  String _formatTime(int ms) {
    final sec = ms ~/ 1000;
    final hundredths = (ms % 1000) ~/ 10;
    final minutes = sec ~/ 60;
    final remainingSec = sec % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSec.toString().padLeft(2, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // PHASE 5 & 6 COMPATIBILITY METHODS
  // ==========================================

  ClipTransform _getInterpolatedTransform(TimelineClip clip, int relativeTimeMs) {
    if (clip.keyframes.isEmpty) {
      return clip.transform;
    }

    final sorted = List<ClipKeyframe>.from(clip.keyframes)
      ..sort((a, b) => a.timeOffsetMs.compareTo(b.timeOffsetMs));

    if (relativeTimeMs <= sorted.first.timeOffsetMs) {
      final k = sorted.first;
      return ClipTransform(x: k.x, y: k.y, scale: k.scale, rotation: k.rotation, opacity: k.opacity);
    }
    if (relativeTimeMs >= sorted.last.timeOffsetMs) {
      final k = sorted.last;
      return ClipTransform(x: k.x, y: k.y, scale: k.scale, rotation: k.rotation, opacity: k.opacity);
    }

    for (int i = 0; i < sorted.length - 1; i++) {
      final k1 = sorted[i];
      final k2 = sorted[i + 1];
      if (relativeTimeMs >= k1.timeOffsetMs && relativeTimeMs <= k2.timeOffsetMs) {
        final double fraction = (relativeTimeMs - k1.timeOffsetMs) / (k2.timeOffsetMs - k1.timeOffsetMs);
        return ClipTransform(
          x: k1.x + (k2.x - k1.x) * fraction,
          y: k1.y + (k2.y - k1.y) * fraction,
          scale: k1.scale + (k2.scale - k1.scale) * fraction,
          rotation: k1.rotation + (k2.rotation - k1.rotation) * fraction,
          opacity: k1.opacity + (k2.opacity - k1.opacity) * fraction,
        );
      }
    }

    return clip.transform;
  }

  void _editOverlayText(TimelineClip clip) {
    final textController = TextEditingController(text: clip.textContent);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141414),
          title: const Text("Edit Text Overlay", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: textController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Enter text...",
              hintStyle: TextStyle(color: Colors.white30),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  clip.textContent = textController.text;
                });
                _pushHistoryState();
                Navigator.pop(context);
              },
              child: const Text("Apply", style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        );
      },
    );
  }

  void _updateTransformParameter(String key, double val) {
    final clip = _selectedClip;
    if (clip == null) return;

    final relativeTimeMs = _currentTimeMs - clip.startInTimelineMs;
    final existingIndex = clip.keyframes.indexWhere(
      (k) => (k.timeOffsetMs - relativeTimeMs).abs() < 150,
    );

    setState(() {
      if (key == 'x') clip.transform.x = val;
      if (key == 'y') clip.transform.y = val;
      if (key == 'scale') clip.transform.scale = val;
      if (key == 'rotation') clip.transform.rotation = val;
      if (key == 'opacity') clip.transform.opacity = val;

      if (existingIndex != -1) {
        final k = clip.keyframes[existingIndex];
        if (key == 'x') k.x = val;
        if (key == 'y') k.y = val;
        if (key == 'scale') k.scale = val;
        if (key == 'rotation') k.rotation = val;
        if (key == 'opacity') k.opacity = val;
      }
    });

    _pushHistoryState();
  }

  void _addBeatMarker() {
    final clip = _selectedClip;
    if (clip == null || _selectedTrack?.type != TrackType.audio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an audio clip to add a beat marker'), backgroundColor: Colors.amber),
      );
      return;
    }

    final relativeTimeMs = _currentTimeMs - clip.startInTimelineMs;
    if (relativeTimeMs >= 0 && relativeTimeMs <= clip.durationMs) {
      setState(() {
        if (!clip.beats.contains(relativeTimeMs)) {
          clip.beats.add(relativeTimeMs);
          clip.beats.sort();
        }
      });
      _pushHistoryState();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beat marker added!'), duration: Duration(milliseconds: 700)),
      );
    }
  }

  void _clearBeatMarkers() {
    final clip = _selectedClip;
    if (clip == null) return;
    setState(() {
      clip.beats.clear();
    });
    _pushHistoryState();
  }

  void _toggleDictation() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dictation speech-to-text not available on this device"), backgroundColor: Colors.amber),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
      });

      if (_recognizedText.isNotEmpty) {
        final textTrack = _project.tracks.firstWhere(
          (t) => t.type == TrackType.text,
          orElse: () => Track(id: 'track_text_1', type: TrackType.text, zOrder: 1, clips: []),
        );

        textTrack.clips.add(
          TimelineClip(
            id: 'dictation_${DateTime.now().millisecondsSinceEpoch}',
            startInTimelineMs: _currentTimeMs,
            durationMs: 3000,
            startInSourceMs: 0,
            transform: ClipTransform(y: 80.0),
            effects: [],
            textContent: _recognizedText,
          ),
        );
        _pushHistoryState();
      }
    } else {
      setState(() {
        _isListening = true;
        _recognizedText = '';
      });
      _speech.listen(
        onResult: (val) => setState(() {
          _recognizedText = val.recognizedWords;
        }),
      );
    }
  }

  void _addOrUpdateKeyframe() {
    final clip = _selectedClip;
    if (clip == null) return;

    final relativeTimeMs = _currentTimeMs - clip.startInTimelineMs;
    if (relativeTimeMs < 0 || relativeTimeMs > clip.durationMs) return;

    final existingIndex = clip.keyframes.indexWhere(
      (k) => (k.timeOffsetMs - relativeTimeMs).abs() < 100,
    );

    setState(() {
      if (existingIndex != -1) {
        final k = clip.keyframes[existingIndex];
        k.x = clip.transform.x;
        k.y = clip.transform.y;
        k.scale = clip.transform.scale;
        k.rotation = clip.transform.rotation;
        k.opacity = clip.transform.opacity;
      } else {
        clip.keyframes.add(
          ClipKeyframe(
            timeOffsetMs: relativeTimeMs,
            x: clip.transform.x,
            y: clip.transform.y,
            scale: clip.transform.scale,
            rotation: clip.transform.rotation,
            opacity: clip.transform.opacity,
          ),
        );
      }
    });

    _pushHistoryState();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keyframe set!'), duration: Duration(milliseconds: 700)),
    );
  }

  void _removeKeyframeAtPlayhead() {
    final clip = _selectedClip;
    if (clip == null) return;

    final relativeTimeMs = _currentTimeMs - clip.startInTimelineMs;

    setState(() {
      clip.keyframes.removeWhere(
        (k) => (k.timeOffsetMs - relativeTimeMs).abs() < 150,
      );
    });

    _pushHistoryState();
  }

  Future<void> _pickAndAddAudio() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.audio,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final audioTrack = _project.tracks.firstWhere(
          (t) => t.type == TrackType.audio,
          orElse: () => Track(id: 'track_audio_1', type: TrackType.audio, zOrder: -1, clips: []),
        );

        final newClip = TimelineClip(
          id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
          sourcePath: path,
          startInTimelineMs: _currentTimeMs,
          durationMs: 8000,
          startInSourceMs: 0,
          transform: ClipTransform(),
          effects: [],
        );

        setState(() {
          audioTrack.clips.add(newClip);
        });
        _pushHistoryState();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking audio: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _addStockMusic(String name, String dummyAssetPath) {
    final audioTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () => Track(id: 'track_audio_1', type: TrackType.audio, zOrder: -1, clips: []),
    );

    final newClip = TimelineClip(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}_stock',
      sourcePath: dummyAssetPath,
      startInTimelineMs: _currentTimeMs,
      durationMs: 10000,
      startInSourceMs: 0,
      transform: ClipTransform(),
      effects: [],
      textContent: name,
    );

    setState(() {
      audioTrack.clips.add(newClip);
    });
    _pushHistoryState();
    setState(() => _activePanel = 'none');
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

        setState(() {
          _isRecording = true;
          _recordedFilePath = path;
          _recordingDurationSec = 0;
          _recognizedText = '';
        });

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        if (_speechAvailable) {
          setState(() => _isListening = true);
          _speech.listen(
            onResult: (val) => setState(() {
              _recognizedText = val.recognizedWords;
            }),
          );
        }

        _updateRecordingTimer();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Recording start failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _updateRecordingTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isRecording) {
        setState(() {
          _recordingDurationSec++;
        });
        _updateRecordingTimer();
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    try {
      final pathResult = await _audioRecorder.stop();
      if (_speechAvailable && _isListening) {
        await _speech.stop();
        setState(() => _isListening = false);
      }

      setState(() {
        _isRecording = false;
      });

      if (pathResult != null) {
        final durationMs = _recordingDurationSec * 1000;
        final audioTrack = _project.tracks.firstWhere(
          (t) => t.type == TrackType.audio,
          orElse: () => Track(id: 'track_audio_1', type: TrackType.audio, zOrder: -1, clips: []),
        );

        final newClip = TimelineClip(
          id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
          sourcePath: pathResult,
          startInTimelineMs: _currentTimeMs,
          durationMs: durationMs > 1000 ? durationMs : 3000,
          startInSourceMs: 0,
          transform: ClipTransform(),
          effects: [],
          textContent: 'Voiceover Recording',
        );

        setState(() {
          audioTrack.clips.add(newClip);
        });

        if (_recognizedText.isNotEmpty) {
          final textTrack = _project.tracks.firstWhere(
            (t) => t.type == TrackType.text,
            orElse: () => Track(id: 'track_text_1', type: TrackType.text, zOrder: 1, clips: []),
          );
          
          textTrack.clips.add(
            TimelineClip(
              id: 'subtitle_${DateTime.now().millisecondsSinceEpoch}',
              startInTimelineMs: _currentTimeMs,
              durationMs: durationMs > 1000 ? durationMs : 3000,
              startInSourceMs: 0,
              transform: ClipTransform(y: 80.0, scale: 1.1),
              effects: [],
              textContent: _recognizedText,
            ),
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Auto-subtitles generated from speech!')),
          );
        }

        _pushHistoryState();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Recording stop failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _synthesizeTTS() async {
    final text = _ttsController.text.trim();
    if (text.isEmpty) return;

    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      if (Platform.isAndroid || Platform.isIOS) {
        await _flutterTts.synthesizeToFile(text, fileName);
      }
      
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(List.filled(1000, 0));
        await _flutterTts.speak(text);
      }

      final audioTrack = _project.tracks.firstWhere(
        (t) => t.type == TrackType.audio,
        orElse: () => Track(id: 'track_audio_1', type: TrackType.audio, zOrder: -1, clips: []),
      );

      final newClip = TimelineClip(
        id: 'tts_${DateTime.now().millisecondsSinceEpoch}',
        sourcePath: filePath,
        startInTimelineMs: _currentTimeMs,
        durationMs: 4000,
        startInSourceMs: 0,
        transform: ClipTransform(),
        effects: [],
        textContent: 'TTS: "$text"',
      );

      setState(() {
        audioTrack.clips.add(newClip);
        _ttsController.clear();
        _activePanel = 'none';
      });

      _pushHistoryState();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI Narrator TTS track added successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("TTS synthesis failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  // ==========================================
  // PHASE 8: COVER SELECTOR & EXPORT UTILITIES
  // ==========================================

  Future<void> _extractCoverFrame(int targetTimeMs) async {
    final mainTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.mainVideo,
      orElse: () => Track(id: '', type: TrackType.mainVideo, zOrder: 0, clips: []),
    );

    if (mainTrack.clips.isEmpty) return;

    // Find the clip at the target timestamp
    TimelineClip? activeClip;
    for (var clip in mainTrack.clips) {
      if (targetTimeMs >= clip.startInTimelineMs &&
          targetTimeMs < clip.startInTimelineMs + clip.durationMs) {
        activeClip = clip;
        break;
      }
    }
    activeClip ??= mainTrack.clips.first;

    if (activeClip.sourcePath == null) return;

    try {
      final relativeMs = targetTimeMs - activeClip.startInTimelineMs;
      final double seekSeconds = (activeClip.startInSourceMs + relativeMs) / 1000.0;

      final tempDir = await getTemporaryDirectory();
      final coverPath = '${tempDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // FFmpeg command to extract one frame
      final String cmd = '-y -ss $seekSeconds -i "${activeClip.sourcePath}" -vframes 1 -q:v 2 "$coverPath"';
      
      await FFmpegKit.execute(cmd);

      if (await File(coverPath).exists()) {
        setState(() {
          _project.thumbnailPath = coverPath;
        });
        _pushHistoryState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover frame updated successfully!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to extract cover: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Build FFmpeg Command for timeline compilation
  String _buildFFmpegExportCommand(String outputPath, String resolution, int targetW, int targetH) {
    final mainTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.mainVideo,
      orElse: () => Track(id: '', type: TrackType.mainVideo, zOrder: 0, clips: []),
    );

    final audioTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () => Track(id: '', type: TrackType.audio, zOrder: -1, clips: []),
    );

    final textTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.text,
      orElse: () => Track(id: '', type: TrackType.text, zOrder: 1, clips: []),
    );

    final List<String> inputs = [];
    final Map<String, int> fileToInputIndex = {};

    void addInput(String path) {
      if (!fileToInputIndex.containsKey(path)) {
        fileToInputIndex[path] = inputs.length;
        inputs.add('-i "$path"');
      }
    }

    for (var clip in mainTrack.clips) {
      if (clip.sourcePath != null) {
        addInput(clip.sourcePath!);
      }
    }

    for (var clip in audioTrack.clips) {
      if (clip.sourcePath != null && !clip.sourcePath!.contains('stock_')) {
        addInput(clip.sourcePath!);
      }
    }

    if (mainTrack.clips.isEmpty) {
      inputs.add('-f lavfi -i "color=c=black:s=${targetW}x${targetH}:d=5"');
    }

    String filterComplex = '';
    String finalVideoNode = '0:v';
    
    if (mainTrack.clips.isNotEmpty) {
      final List<String> concatNodes = [];
      for (int i = 0; i < mainTrack.clips.length; i++) {
        final clip = mainTrack.clips[i];
        final inputIdx = fileToInputIndex[clip.sourcePath] ?? 0;
        final startSec = clip.startInSourceMs / 1000.0;
        final durationSec = clip.durationMs / 1000.0;
        
        String node = '[v_trim_$i]';
        String filter = '[$inputIdx:v]trim=start=$startSec:duration=$durationSec,setpts=PTS-STARTPTS,scale=${targetW}:${targetH}:force_original_aspect_ratio=decrease,pad=${targetW}:${targetH}:(ow-iw)/2:(oh-ih)/2:black';

        final adjust = clip.effects.firstWhere((e) => e.type == 'color_adjust', orElse: () => AdjustmentEffect(id: '')) as AdjustmentEffect;
        if (adjust.id.isNotEmpty) {
          filter += ',eq=brightness=${adjust.brightness}:contrast=${adjust.contrast}:saturation=${adjust.saturation}';
        }

        final filterEffect = clip.effects.firstWhere((e) => e.type == 'lut_filter', orElse: () => FilterEffect(id: '', filterName: 'none')) as FilterEffect;
        if (filterEffect.filterName != 'none') {
          if (filterEffect.filterName == 'sepia') {
            filter += ',colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131';
          } else if (filterEffect.filterName == 'grayscale') {
            filter += ',hue=s=0';
          }
        }

        if (clip.isAiEnhanced) {
          filter += ',eq=contrast=1.2:saturation=1.3';
        }

        filterComplex += '$filter$node;';
        concatNodes.add(node);
      }

      if (concatNodes.length > 1) {
        String concatInputs = concatNodes.join('');
        filterComplex += '${concatInputs}concat=n=${concatNodes.length}:v=1:a=0[main_concat_v];';
        finalVideoNode = '[main_concat_v]';
      } else {
        finalVideoNode = concatNodes.first;
      }
    }

    String textOverlayNode = finalVideoNode;
    if (textTrack.clips.isNotEmpty) {
      for (int i = 0; i < textTrack.clips.length; i++) {
        final clip = textTrack.clips[i];
        final startSec = clip.startInTimelineMs / 1000.0;
        final endSec = (clip.startInTimelineMs + clip.durationMs) / 1000.0;
        final text = clip.textContent ?? '';
        final double xPos = targetW / 2;
        final double yPos = targetH / 2 + clip.transform.y;

        final nextNode = '[text_v_$i]';
        filterComplex += '$textOverlayNode drawtext=text=\'$text\':fontcolor=white:fontsize=36:x=$xPos-text_w/2:y=$yPos-text_h/2:enable=\'between(t,$startSec,$endSec)\'$nextNode;';
        textOverlayNode = nextNode;
      }
    }

    String finalAudioNode = '0:a';
    final List<String> audioNodes = [];

    if (mainTrack.clips.isNotEmpty) {
      final List<String> concatAudioNodes = [];
      for (int i = 0; i < mainTrack.clips.length; i++) {
        final clip = mainTrack.clips[i];
        final inputIdx = fileToInputIndex[clip.sourcePath] ?? 0;
        final startSec = clip.startInSourceMs / 1000.0;
        final durationSec = clip.durationMs / 1000.0;
        
        String node = '[a_trim_$i]';
        filterComplex += '[$inputIdx:a]atrim=start=$startSec:duration=$durationSec,asetpts=PTS-STARTPTS,volume=${clip.volume}$node;';
        concatAudioNodes.add(node);
      }

      if (concatAudioNodes.length > 1) {
        String concatInputs = concatAudioNodes.join('');
        filterComplex += '${concatInputs}concat=n=${concatAudioNodes.length}:v=0:a=1[main_concat_a];';
        audioNodes.add('[main_concat_a]');
      } else {
        audioNodes.add(concatAudioNodes.first);
      }
    }

    for (int i = 0; i < audioTrack.clips.length; i++) {
      final clip = audioTrack.clips[i];
      if (clip.sourcePath != null && !clip.sourcePath!.contains('stock_')) {
        final inputIdx = fileToInputIndex[clip.sourcePath]!;
        final startSec = clip.startInSourceMs / 1000.0;
        final durationSec = clip.durationMs / 1000.0;

        String node = '[a_overlay_$i]';
        filterComplex += '[$inputIdx:a]atrim=start=$startSec:duration=$durationSec,asetpts=PTS-STARTPTS,volume=${clip.volume},adelay=${clip.startInTimelineMs}|${clip.startInTimelineMs}$node;';
        audioNodes.add(node);
      }
    }

    if (audioNodes.length > 1) {
      String mixInputs = audioNodes.join('');
      filterComplex += '${mixInputs}amix=inputs=${audioNodes.length}:duration=first[mixed_a]';
      finalAudioNode = '[mixed_a]';
    } else if (audioNodes.isNotEmpty) {
      finalAudioNode = audioNodes.first;
    } else {
      inputs.add('-f lavfi -i "anullsrc=cl=mono:r=44100"');
      finalAudioNode = '${inputs.length - 1}:a';
    }

    if (filterComplex.endsWith(';')) {
      filterComplex = filterComplex.substring(0, filterComplex.length - 1);
    }

    final String inputArgs = inputs.join(' ');
    String complexFilterArg = '';
    String mapArgs = '';
    
    if (filterComplex.isNotEmpty) {
      complexFilterArg = '-filter_complex "$filterComplex"';
      mapArgs = '-map "$textOverlayNode" -map "$finalAudioNode"';
    } else {
      mapArgs = '-map 0:v -map 0:a';
    }

    return '$inputArgs $complexFilterArg $mapArgs -c:v libx264 -preset ultrafast -c:a aac -shortest "$outputPath"';
  }

  // Trigger non-destructive export compile pipeline
  Future<void> _startRenderPipeline(String resolution, int targetW, int targetH) async {
    Navigator.of(context).pop(); // close settings panel

    double renderProgressPercent = 0.0;
    bool isCompleted = false;
    String statusMessage = "Building filter graph...";

    // Open progress indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Register callback to update modal progress bar
            FFmpegKitConfig.enableStatisticsCallback((stats) {
              final totalDurationMs = _calculateTotalDuration();
              if (totalDurationMs > 0) {
                final double currentProgress = (stats.getTime() / totalDurationMs) * 100;
                setModalState(() {
                  renderProgressPercent = currentProgress.clamp(0.0, 100.0);
                  statusMessage = "Encoding frames: ${renderProgressPercent.toStringAsFixed(0)}%";
                });
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF161618),
              title: const Text("Exporting Video", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: renderProgressPercent / 100.0,
                    color: Colors.tealAccent,
                    backgroundColor: Colors.white12,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 12),
                  const Text("This might take a minute depending on timeline elements.", style: TextStyle(color: Colors.white30, fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final tempOutPath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final cmd = _buildFFmpegExportCommand(tempOutPath, resolution, targetW, targetH);
      debugPrint("Executing FFmpeg command: $cmd");

      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      Navigator.of(context).pop(); // Close progress dialog

      if (ReturnCode.isSuccess(returnCode)) {
        // Save to public gallery via gal
        await Gal.putVideo(tempOutPath, album: 'MyVideoEditor');
        
        // Clean up temp file
        final tempFile = File(tempOutPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        // Show Export Success completed screen
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161618),
              title: const Text("Export Completed! 🎉", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: const Text(
                "Your finished masterpiece is saved to your public gallery under the album 'MyVideoEditor'.",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Launch public gallery (Gal supports open)
                    Gal.open();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                  child: const Text("Open Gallery"),
                ),
              ],
            );
          },
        );
      } else {
        final logs = await session.getLogs();
        final failMsg = logs.isNotEmpty ? logs.last.getMessage() : "Unknown FFmpeg error";
        throw Exception(failMsg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Open Export settings dialog
  void _openExportSettingsDialog() {
    final nameController = TextEditingController(text: _project.name);
    double coverSliderVal = 0.0;
    String selectedRes = '1080p';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final totalDuration = _calculateTotalDuration();
            
            // Width and heights based on selection
            int targetW = 1080;
            int targetH = 1920;
            if (selectedRes == '720p') {
              targetW = 720;
              targetH = 1280;
            } else if (selectedRes == '480p') {
              targetW = 480;
              targetH = 854;
            }

            if (_project.aspectRatio == EditorAspectRatio.ratio16to9) {
              final tmp = targetW;
              targetW = targetH;
              targetH = tmp;
            } else if (_project.aspectRatio == EditorAspectRatio.ratio1to1) {
              targetH = targetW;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 24.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Export Masterpiece & Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Rename TextField
                    const Text("Draft Name:", style: TextStyle(fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _project.name = val;
                        });
                        _saveProjectState();
                      },
                    ),
                    const SizedBox(height: 16),
                    // Protection Mode Switch
                    SwitchListTile(
                      title: const Text("Draft Protection Mode", style: TextStyle(fontSize: 13, color: Colors.white70)),
                      subtitle: const Text("Prevents accidental deletion from the home screen", style: TextStyle(fontSize: 10, color: Colors.white30)),
                      value: _project.isProtected,
                      activeColor: Colors.tealAccent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setModalState(() {
                          _project.isProtected = val;
                        });
                        setState(() {});
                        _pushHistoryState();
                      },
                    ),
                    const Divider(color: Colors.white12, height: 28),
                    // Cover selection section
                    const Text("Choose Cover Frame:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Cover preview
                        Container(
                          width: 80,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade900),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _project.thumbnailPath != null
                              ? Image.file(File(_project.thumbnailPath!), fit: BoxFit.cover)
                              : const Center(child: Icon(Icons.photo_outlined, color: Colors.white24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Slider(
                                value: coverSliderVal,
                                min: 0.0,
                                max: 1.0,
                                activeColor: Colors.tealAccent,
                                inactiveColor: Colors.white24,
                                onChanged: (val) {
                                  setModalState(() {
                                    coverSliderVal = val;
                                  });
                                  // Seek preview player to the timestamp
                                  _seekTo((val * totalDuration).toInt());
                                },
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Time: ${_formatTime((coverSliderVal * totalDuration).toInt())}", style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                  ElevatedButton(
                                    onPressed: () async {
                                      final targetMs = (coverSliderVal * totalDuration).toInt();
                                      await _extractCoverFrame(targetMs);
                                      setModalState(() {});
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.tealAccent.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    child: const Text("Capture Cover", style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 28),
                    // Resolution selector
                    const Text("Resolution Settings:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['1080p', '720p', '480p'].map((res) {
                        final isSelected = selectedRes == res;
                        return ChoiceChip(
                          label: Text(res),
                          selected: isSelected,
                          selectedColor: Colors.tealAccent,
                          labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                          onSelected: (_) {
                            setModalState(() {
                              selectedRes = res;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    // Export Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _startRenderPipeline(selectedRes, targetW, targetH),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Render & Export", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // PHASE 4 COMPATIBILITY EDITING FUNCTIONS
  // ==========================================

  void _splitSelectedClip() {
    final clip = _selectedClip;
    final track = _selectedTrack;
    if (clip == null || track == null) return;

    if (_currentTimeMs > clip.startInTimelineMs &&
        _currentTimeMs < clip.startInTimelineMs + clip.durationMs) {
      
      final leftDuration = _currentTimeMs - clip.startInTimelineMs;
      final rightDuration = (clip.startInTimelineMs + clip.durationMs) - _currentTimeMs;

      final rightClip = TimelineClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}_split',
        sourcePath: clip.sourcePath,
        startInTimelineMs: _currentTimeMs,
        durationMs: rightDuration,
        startInSourceMs: clip.startInSourceMs + leftDuration,
        speed: clip.speed,
        volume: clip.volume,
        transform: ClipTransform(
          x: clip.transform.x,
          y: clip.transform.y,
          scale: clip.transform.scale,
          rotation: clip.transform.rotation,
          opacity: clip.transform.opacity,
        ),
        effects: List.from(clip.effects),
        textContent: clip.textContent,
        transitionType: 'none',
        beats: List.from(clip.beats),
        keyframes: List.from(clip.keyframes),
        maskType: clip.maskType,
        maskSize: clip.maskSize,
        maskFeather: clip.maskFeather,
        blendMode: clip.blendMode,
        chromaKeyColor: clip.chromaKeyColor,
        chromaKeyTolerance: clip.chromaKeyTolerance,
        chromaKeySpill: clip.chromaKeySpill,
        isAiBackgroundRemoved: clip.isAiBackgroundRemoved,
        isAiEnhanced: clip.isAiEnhanced,
        voiceEffect: clip.voiceEffect,
        isAiDenoised: clip.isAiDenoised,
      );

      clip.durationMs = leftDuration;

      final index = track.clips.indexOf(clip);
      track.clips.insert(index + 1, rightClip);

      _selectedClip = null;
      _selectedTrack = null;
      _pushHistoryState();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clip split successfully'), duration: Duration(seconds: 1)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move the playhead inside the clip to split'), backgroundColor: Colors.amber),
      );
    }
  }

  void _deleteSelectedClip() {
    final clip = _selectedClip;
    final track = _selectedTrack;
    if (clip == null || track == null) return;

    track.clips.remove(clip);

    if (track.type == TrackType.mainVideo) {
      int currentOffset = 0;
      for (var c in track.clips) {
        c.startInTimelineMs = currentOffset;
        currentOffset += c.durationMs;
      }
    }

    _selectedClip = null;
    _selectedTrack = null;
    _activePanel = 'none';
    _currentTimeMs = 0;
    
    _initializeVideoPlayer();
    _pushHistoryState();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clip deleted'), duration: Duration(seconds: 1)),
    );
  }

  void _updateClipSpeed(double newSpeed) {
    final clip = _selectedClip;
    final track = _selectedTrack;
    if (clip == null || track == null) return;

    final double sourceDuration = clip.durationMs * clip.speed;
    final int newDurationMs = (sourceDuration / newSpeed).round();

    clip.speed = newSpeed;
    clip.durationMs = newDurationMs;

    if (track.type == TrackType.mainVideo) {
      int currentOffset = 0;
      for (var c in track.clips) {
        c.startInTimelineMs = currentOffset;
        currentOffset += c.durationMs;
      }
    }

    _pushHistoryState();
  }

  void _updateClipVolume(double newVolume) {
    final clip = _selectedClip;
    if (clip == null) return;

    clip.volume = newVolume;
    _pushHistoryState();
  }

  void _applyFilter(String filterName) {
    final clip = _selectedClip;
    if (clip == null) return;

    clip.effects.removeWhere((e) => e.type == 'lut_filter');

    if (filterName != 'none') {
      clip.effects.add(
        FilterEffect(
          id: 'filter_${DateTime.now().millisecondsSinceEpoch}',
          filterName: filterName,
        ),
      );
    }
    _pushHistoryState();
  }

  AdjustmentEffect _getOrAddAdjustmentEffect(TimelineClip clip) {
    final adjust = clip.effects.firstWhere(
      (e) => e.type == 'color_adjust',
      orElse: () {
        final newAdjust = AdjustmentEffect(
          id: 'adjust_${DateTime.now().millisecondsSinceEpoch}',
          brightness: 0.0,
          contrast: 1.0,
          saturation: 1.0,
        );
        clip.effects.add(newAdjust);
        return newAdjust;
      },
    ) as AdjustmentEffect;
    return adjust;
  }

  void _updateAdjustment(String key, double value) {
    final clip = _selectedClip;
    if (clip == null) return;

    final adjust = _getOrAddAdjustmentEffect(clip);
    setState(() {
      if (key == 'brightness') adjust.brightness = value;
      if (key == 'contrast') adjust.contrast = value;
      if (key == 'saturation') adjust.saturation = value;
    });

    _pushHistoryState();
  }

  void _addTextOverlay() {
    final textTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.text,
      orElse: () => Track(id: 'track_text_1', type: TrackType.text, zOrder: 1, clips: []),
    );

    final newClip = TimelineClip(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      startInTimelineMs: _currentTimeMs,
      durationMs: 3000,
      startInSourceMs: 0,
      transform: ClipTransform(scale: 1.2),
      effects: [],
      textContent: "Tap to edit text",
    );

    textTrack.clips.add(newClip);
    _pushHistoryState();
  }

  void _addStickerOverlay(String emoji) {
    final stickerTrack = _project.tracks.firstWhere(
      (t) => t.type == TrackType.sticker,
      orElse: () => Track(id: 'track_sticker_1', type: TrackType.sticker, zOrder: 2, clips: []),
    );

    final newClip = TimelineClip(
      id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
      startInTimelineMs: _currentTimeMs,
      durationMs: 3000,
      startInSourceMs: 0,
      transform: ClipTransform(scale: 1.5),
      effects: [],
      textContent: emoji,
    );

    stickerTrack.clips.add(newClip);
    _pushHistoryState();
  }

  // ==========================================
  // PREVIEW RENDERER (WITH MASKS, BLEND MODES, CHROMA KEY, KEYFRAMES & AI ENHANCEMENTS)
  // ==========================================

  Widget _buildPreviewPlayer() {
    if (_previewController == null || !_previewController!.value.isInitialized) {
      return Center(
        child: Icon(
          Icons.movie_filter_outlined,
          size: 64,
          color: Colors.tealAccent.shade400.withOpacity(0.4),
        ),
      );
    }

    Widget videoWidget = VideoPlayer(_previewController!);

    final activeClip = _currentPlayingClip;
    if (activeClip != null) {
      if (activeClip.isAiEnhanced) {
        const double c = 1.25;
        const double t = (1.0 - c) / 2.0 * 255;
        const double s = 1.35;
        const double lr = 0.213 * (1.0 - s);
        const double lg = 0.715 * (1.0 - s);
        const double lb = 0.072 * (1.0 - s);
        
        final enhanceContrast = [
          c, 0.0, 0.0, 0.0, t,
          0.0, c, 0.0, 0.0, t,
          0.0, 0.0, c, 0.0, t,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
        final enhanceSaturation = [
          lr + s, lg, lb, 0.0, 0.0,
          lr, lg + s, lb, 0.0, 0.0,
          lr, lg, lb + s, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];

        videoWidget = ColorFiltered(
          colorFilter: ColorFilter.matrix(enhanceContrast),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(enhanceSaturation),
            child: videoWidget,
          ),
        );
      }

      final filter = activeClip.effects.firstWhere(
        (e) => e.type == 'lut_filter',
        orElse: () => FilterEffect(id: '', filterName: 'none'),
      ) as FilterEffect;

      if (filter.filterName != 'none') {
        List<double>? matrix;
        if (filter.filterName == 'sepia') {
          matrix = [
            0.393, 0.769, 0.189, 0, 0,
            0.349, 0.686, 0.168, 0, 0,
            0.272, 0.534, 0.131, 0, 0,
            0, 0, 0, 1, 0,
          ];
        } else if (filter.filterName == 'grayscale') {
          matrix = [
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ];
        } else if (filter.filterName == 'vintage') {
          matrix = [
            0.9, 0, 0, 0, 0,
            0, 0.8, 0, 0, 0,
            0, 0, 0.6, 0, 0,
            0, 0, 0, 1, 0,
          ];
        } else if (filter.filterName == 'cool') {
          matrix = [
            1, 0, 0, 0, -10,
            0, 1, 0, 0, 5,
            0, 0, 1.2, 0, 20,
            0, 0, 0, 1, 0,
          ];
        } else if (filter.filterName == 'warm') {
          matrix = [
            1.2, 0, 0, 0, 20,
            0, 1, 0, 0, 5,
            0, 0, 0.8, 0, -10,
            0, 0, 0, 1, 0,
          ];
        }

        if (matrix != null) {
          videoWidget = ColorFiltered(
            colorFilter: ColorFilter.matrix(matrix),
            child: videoWidget,
          );
        }
      }

      final adjust = activeClip.effects.firstWhere(
        (e) => e.type == 'color_adjust',
        orElse: () => AdjustmentEffect(id: ''),
      ) as AdjustmentEffect;

      if (adjust.id.isNotEmpty) {
        final double b = adjust.brightness * 255;
        final brightnessMatrix = [
          1.0, 0.0, 0.0, 0.0, b,
          0.0, 1.0, 0.0, 0.0, b,
          0.0, 0.0, 1.0, 0.0, b,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
        final double c = adjust.contrast;
        final double t = (1.0 - c) / 2.0 * 255;
        final contrastMatrix = [
          c, 0.0, 0.0, 0.0, t,
          0.0, c, 0.0, 0.0, t,
          0.0, 0.0, c, 0.0, t,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];
        final double s = adjust.saturation;
        final double lr = 0.213 * (1.0 - s);
        final double lg = 0.715 * (1.0 - s);
        final double lb = 0.072 * (1.0 - s);
        final saturationMatrix = [
          lr + s, lg, lb, 0.0, 0.0,
          lr, lg + s, lb, 0.0, 0.0,
          lr, lg, lb + s, 0.0, 0.0,
          0.0, 0.0, 0.0, 1.0, 0.0,
        ];

        videoWidget = ColorFiltered(
          colorFilter: ColorFilter.matrix(brightnessMatrix),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(contrastMatrix),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(saturationMatrix),
              child: videoWidget,
            ),
          ),
        );
      }
    }

    final List<Widget> overlayWidgets = [];

    for (var track in _project.tracks) {
      if (track.type == TrackType.text || track.type == TrackType.sticker) {
        for (var clip in track.clips) {
          if (_currentTimeMs >= clip.startInTimelineMs &&
              _currentTimeMs < clip.startInTimelineMs + clip.durationMs) {
            
            final relativeTime = _currentTimeMs - clip.startInTimelineMs;
            final interpolatedTransform = _getInterpolatedTransform(clip, relativeTime);

            Widget child = Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedClip?.id == clip.id ? Colors.tealAccent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: track.type == TrackType.text
                  ? GestureDetector(
                      onDoubleTap: () => _editOverlayText(clip),
                      child: Text(
                        clip.textContent ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))
                          ],
                        ),
                      ),
                    )
                  : Text(
                      clip.textContent ?? '😀',
                      style: const TextStyle(fontSize: 32),
                    ),
            );

            if (clip.isAiBackgroundRemoved) {
              child = Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.tealAccent.withOpacity(0.6), blurRadius: 16, spreadRadius: 2),
                  ],
                ),
                child: child,
              );
            }

            if (clip.chromaKeyColor != null) {
              child = ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  1, 0, 0, 0, 0,
                  0, 0, 0, 0, 0,
                  0, 0, 1, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: child,
              );
            }

            if (clip.blendMode != 'normal') {
              BlendMode flutterBlendMode = BlendMode.srcOver;
              if (clip.blendMode == 'multiply') flutterBlendMode = BlendMode.multiply;
              if (clip.blendMode == 'screen') flutterBlendMode = BlendMode.screen;
              if (clip.blendMode == 'overlay') flutterBlendMode = BlendMode.overlay;
              if (clip.blendMode == 'darken') flutterBlendMode = BlendMode.darken;
              if (clip.blendMode == 'lighten') flutterBlendMode = BlendMode.lighten;

              child = ShaderMask(
                blendMode: flutterBlendMode,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Colors.white],
                ).createShader(bounds),
                child: child,
              );
            }

            if (clip.maskType != 'none') {
              child = ClipPath(
                clipper: MaskClipper(clip.maskType, clip.maskSize, clip.maskFeather),
                child: child,
              );
            }

            overlayWidgets.add(
              Positioned(
                left: 100.0 + interpolatedTransform.x.toDouble(),
                top: 100.0 + interpolatedTransform.y.toDouble(),
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _updateTransformParameter('x', interpolatedTransform.x + details.delta.dx);
                      _updateTransformParameter('y', interpolatedTransform.y + details.delta.dy);
                    });
                  },
                  onPanEnd: (_) => _pushHistoryState(),
                  child: Transform.rotate(
                    angle: interpolatedTransform.rotation * 3.14159 / 180,
                    child: Transform.scale(
                      scale: interpolatedTransform.scale,
                      child: Opacity(
                        opacity: interpolatedTransform.opacity,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
      }
    }

    return AspectRatio(
      aspectRatio: _project.aspectRatio.value,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          videoWidget,
          ...overlayWidgets,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDuration = _calculateTotalDuration();
    final totalDurationStr = _formatTime(totalDuration);
    final currentTimeStr = _formatTime(_currentTimeMs);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            _saveProjectState();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          _project.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.undo, color: _historyManager.canUndo ? Colors.white : Colors.white24),
            onPressed: _historyManager.canUndo ? _undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo, color: _historyManager.canRedo ? Colors.white : Colors.white24),
            onPressed: _historyManager.canRedo ? _redo : null,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
            child: ElevatedButton(
              onPressed: _openExportSettingsDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Export", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade900, width: 1.5),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildPreviewPlayer(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "$currentTimeStr / $totalDurationStr",
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white38, size: 18),
                      SizedBox(
                        width: 100,
                        child: Slider(
                          value: _zoomScale,
                          min: 0.2,
                          max: 3.0,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (val) {
                            setState(() => _zoomScale = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 40, color: Colors.tealAccent),
                    onPressed: _togglePlayPause,
                  ),
                ],
              ),
            ),
            _buildToolbarPanel(),
            Expanded(
              flex: 5,
              child: _buildTimeline(totalDuration),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DYNAMIC PANEL BUILDERS
  // ==========================================

  Widget _buildToolbarPanel() {
    if (_activePanel == 'speed' && _selectedClip != null) {
      return _buildSpeedPanel();
    } else if (_activePanel == 'volume' && _selectedClip != null) {
      return _buildVolumePanel();
    } else if (_activePanel == 'filters' && _selectedClip != null) {
      return _buildFiltersPanel();
    } else if (_activePanel == 'adjust' && _selectedClip != null) {
      return _buildAdjustPanel();
    } else if (_activePanel == 'stickers') {
      return _buildStickersPanel();
    } else if (_activePanel == 'transitions' && _selectedClip != null) {
      return _buildTransitionsPanel();
    } else if (_activePanel == 'audio') {
      return _buildAudioPanel();
    } else if (_activePanel == 'voiceover') {
      return _buildVoiceoverPanel();
    } else if (_activePanel == 'tts') {
      return _buildTTSPanel();
    } else if (_activePanel == 'keyframes' && _selectedClip != null) {
      return _buildKeyframesPanel();
    } else if (_activePanel == 'mask' && _selectedClip != null) {
      return _buildMaskPanel();
    } else if (_activePanel == 'blend' && _selectedClip != null) {
      return _buildBlendPanel();
    } else if (_activePanel == 'chroma' && _selectedClip != null) {
      return _buildChromaPanel();
    } else if (_activePanel == 'ai' && _selectedClip != null) {
      return _buildAIToolsPanel();
    }
    
    return _buildMainMenuPanel();
  }

  Widget _buildMainMenuPanel() {
    final hasSelection = _selectedClip != null;
    final isAudioSelected = hasSelection && _selectedTrack?.type == TrackType.audio;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildToolBtn(
            icon: Icons.splitscreen_rounded,
            label: "Split",
            onTap: hasSelection ? _splitSelectedClip : null,
          ),
          _buildToolBtn(
            icon: Icons.delete_outline_rounded,
            label: "Delete",
            color: Colors.redAccent,
            onTap: hasSelection ? _deleteSelectedClip : null,
          ),
          _buildToolBtn(
            icon: Icons.auto_awesome_rounded,
            label: "AI Tools",
            onTap: hasSelection ? () => setState(() => _activePanel = 'ai') : null,
          ),
          _buildToolBtn(
            icon: Icons.vpn_key_rounded,
            label: "Keyframes",
            onTap: hasSelection ? () => setState(() => _activePanel = 'keyframes') : null,
          ),
          _buildToolBtn(
            icon: Icons.masks_rounded,
            label: "Mask",
            onTap: hasSelection ? () => setState(() => _activePanel = 'mask') : null,
          ),
          _buildToolBtn(
            icon: Icons.difference_rounded,
            label: "Blend",
            onTap: hasSelection ? () => setState(() => _activePanel = 'blend') : null,
          ),
          _buildToolBtn(
            icon: Icons.filter_b_and_w_rounded,
            label: "Chroma Key",
            onTap: hasSelection ? () => setState(() => _activePanel = 'chroma') : null,
          ),
          _buildToolBtn(
            icon: Icons.speed_rounded,
            label: "Speed",
            onTap: hasSelection
                ? () => setState(() => _activePanel = 'speed')
                : null,
          ),
          _buildToolBtn(
            icon: Icons.volume_up_rounded,
            label: "Volume",
            onTap: hasSelection
                ? () => setState(() => _activePanel = 'volume')
                : null,
          ),
          _buildToolBtn(
            icon: Icons.music_note_rounded,
            label: "Audio",
            onTap: () => setState(() => _activePanel = 'audio'),
          ),
          _buildToolBtn(
            icon: Icons.mic_none_rounded,
            label: "Voiceover",
            onTap: () => setState(() => _activePanel = 'voiceover'),
          ),
          _buildToolBtn(
            icon: Icons.record_voice_over_rounded,
            label: "AI Speech",
            onTap: () => setState(() => _activePanel = 'tts'),
          ),
          _buildToolBtn(
            icon: Icons.push_pin_outlined,
            label: "Add Beat",
            onTap: isAudioSelected ? _addBeatMarker : null,
          ),
          _buildToolBtn(
            icon: Icons.pin_drop_rounded,
            label: "Clear Beats",
            onTap: isAudioSelected && clipHasBeats() ? _clearBeatMarkers : null,
          ),
          _buildToolBtn(
            icon: Icons.photo_filter_rounded,
            label: "Filters",
            onTap: hasSelection
                ? () => setState(() => _activePanel = 'filters')
                : null,
          ),
          _buildToolBtn(
            icon: Icons.tune_rounded,
            label: "Adjust",
            onTap: hasSelection
                ? () => setState(() => _activePanel = 'adjust')
                : null,
          ),
          _buildToolBtn(
            icon: Icons.title_rounded,
            label: "Add Text",
            onTap: () {
              _addTextOverlay();
              setState(() => _activePanel = 'none');
            },
          ),
          _buildToolBtn(
            icon: _isListening ? Icons.hearing_rounded : Icons.keyboard_voice_rounded,
            label: _isListening ? "Listening..." : "Dictate",
            color: _isListening ? Colors.redAccent : Colors.white,
            onTap: _toggleDictation,
          ),
          _buildToolBtn(
            icon: Icons.sentiment_satisfied_alt_rounded,
            label: "Stickers",
            onTap: () => setState(() => _activePanel = 'stickers'),
          ),
          _buildToolBtn(
            icon: Icons.style_outlined,
            label: "Transition",
            onTap: hasSelection && _selectedTrack?.type == TrackType.mainVideo
                ? () => setState(() => _activePanel = 'transitions')
                : null,
          ),
        ],
      ),
    );
  }

  bool clipHasBeats() {
    return _selectedClip != null && _selectedClip!.beats.isNotEmpty;
  }

  // AI Tools Panel (Phase 7)
  Widget _buildAIToolsPanel() {
    final clip = _selectedClip!;

    return _buildPanelWrapper(
      title: "AI Tools Suite",
      child: Column(
        children: [
          SwitchListTile(
            title: const Text("AI Background Cutout (PIP/Stickers)", style: TextStyle(fontSize: 13, color: Colors.white70)),
            value: clip.isAiBackgroundRemoved,
            activeColor: Colors.tealAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                clip.isAiBackgroundRemoved = val;
              });
              _pushHistoryState();
            },
          ),
          SwitchListTile(
            title: const Text("AI Auto-Color Enhancer", style: TextStyle(fontSize: 13, color: Colors.white70)),
            subtitle: const Text("Bumps dynamic contrast and saturation", style: TextStyle(fontSize: 10, color: Colors.white30)),
            value: clip.isAiEnhanced,
            activeColor: Colors.tealAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                clip.isAiEnhanced = val;
              });
              _pushHistoryState();
            },
          ),
          SwitchListTile(
            title: const Text("AI Audio Denoise", style: TextStyle(fontSize: 13, color: Colors.white70)),
            subtitle: const Text("Reduces background hum and wind noise", style: TextStyle(fontSize: 10, color: Colors.white30)),
            value: clip.isAiDenoised,
            activeColor: Colors.tealAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                clip.isAiDenoised = val;
              });
              _pushHistoryState();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("AI Voice Morph Effects: ", style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildVoiceChip('none', 'Normal'),
                _buildVoiceChip('chipmunk', 'Chipmunk'),
                _buildVoiceChip('deep', 'Deep Voice'),
                _buildVoiceChip('robot', 'Robot Echo'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceChip(String value, String label) {
    final clip = _selectedClip!;
    final isSelected = clip.voiceEffect == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        selectedColor: Colors.tealAccent,
        labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
        onSelected: (_) {
          setState(() {
            clip.voiceEffect = value;
          });
          _pushHistoryState();
        },
      ),
    );
  }

  // Keyframes Settings Panel
  Widget _buildKeyframesPanel() {
    final clip = _selectedClip!;
    final relativeTime = _currentTimeMs - clip.startInTimelineMs;
    final isAtKeyframe = clip.keyframes.any(
      (k) => (k.timeOffsetMs - relativeTime).abs() < 150,
    );

    return _buildPanelWrapper(
      title: "Keyframe Editor",
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton.icon(
                onPressed: _addOrUpdateKeyframe,
                icon: const Icon(Icons.add_box_rounded, size: 16),
                label: Text(isAtKeyframe ? "Update Keyframe" : "Add Keyframe"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
              ),
              ElevatedButton.icon(
                onPressed: isAtKeyframe ? _removeKeyframeAtPlayhead : null,
                icon: const Icon(Icons.disabled_by_default_rounded, size: 16),
                label: const Text("Delete Keyframe"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAdjustmentSlider("Position X", clip.transform.x, -200, 200, (val) {
            _updateTransformParameter('x', val);
          }),
          _buildAdjustmentSlider("Position Y", clip.transform.y, -200, 200, (val) {
            _updateTransformParameter('y', val);
          }),
          _buildAdjustmentSlider("Scale", clip.transform.scale, 0.25, 4.0, (val) {
            _updateTransformParameter('scale', val);
          }),
          _buildAdjustmentSlider("Rotation", clip.transform.rotation, -180, 180, (val) {
            _updateTransformParameter('rotation', val);
          }),
        ],
      ),
    );
  }

  // Mask Panel
  Widget _buildMaskPanel() {
    final clip = _selectedClip!;
    final maskOptions = [
      {'name': 'None', 'id': 'none'},
      {'name': 'Linear Split', 'id': 'linear'},
      {'name': 'Circle Mask', 'id': 'circle'},
      {'name': 'Rectangle Mask', 'id': 'rectangle'},
      {'name': 'Mirror Strip', 'id': 'mirror'},
    ];

    return _buildPanelWrapper(
      title: "Shape Mask Overlays",
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: maskOptions.length,
              itemBuilder: (context, index) {
                final option = maskOptions[index];
                final isSelected = clip.maskType == option['id'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: ChoiceChip(
                    label: Text(option['name']!, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: Colors.tealAccent,
                    onSelected: (_) {
                      setState(() {
                        clip.maskType = option['id']!;
                      });
                      _pushHistoryState();
                    },
                  ),
                );
              },
            ),
          ),
          if (clip.maskType != 'none') ...[
            const SizedBox(height: 8),
            _buildAdjustmentSlider("Mask Size", clip.maskSize, 0.1, 2.0, (val) {
              setState(() {
                clip.maskSize = val;
              });
              _pushHistoryState();
            }),
          ]
        ],
      ),
    );
  }

  // Blend modes Panel
  Widget _buildBlendPanel() {
    final clip = _selectedClip!;
    final blendOptions = [
      {'name': 'Normal', 'id': 'normal'},
      {'name': 'Multiply', 'id': 'multiply'},
      {'name': 'Screen', 'id': 'screen'},
      {'name': 'Overlay', 'id': 'overlay'},
      {'name': 'Darken', 'id': 'darken'},
      {'name': 'Lighten', 'id': 'lighten'},
    ];

    return _buildPanelWrapper(
      title: "Blend Modes Options",
      child: SizedBox(
        height: 48,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: blendOptions.length,
          itemBuilder: (context, index) {
            final option = blendOptions[index];
            final isSelected = clip.blendMode == option['id'];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: ChoiceChip(
                label: Text(option['name']!),
                selected: isSelected,
                selectedColor: Colors.tealAccent,
                onSelected: (_) {
                  setState(() {
                    clip.blendMode = option['id']!;
                  });
                  _pushHistoryState();
                },
              ),
            );
          },
        ),
      ),
    );
  }

  // Chroma Key Panel
  Widget _buildChromaPanel() {
    final clip = _selectedClip!;
    final isChromaActive = clip.chromaKeyColor != null;

    return _buildPanelWrapper(
      title: "Chroma Key (Green Screen Removal)",
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Enable Chroma Keying", style: TextStyle(color: Colors.white70)),
              Switch(
                value: isChromaActive,
                activeColor: Colors.tealAccent,
                onChanged: (val) {
                  setState(() {
                    clip.chromaKeyColor = val ? '#00ff00' : null;
                  });
                  _pushHistoryState();
                },
              ),
            ],
          ),
          if (isChromaActive) ...[
            const SizedBox(height: 8),
            _buildAdjustmentSlider("Tolerance", clip.chromaKeyTolerance, 0.05, 1.0, (val) {
              setState(() {
                clip.chromaKeyTolerance = val;
              });
              _pushHistoryState();
            }),
            _buildAdjustmentSlider("Spill Cleaner", clip.chromaKeySpill, 0.0, 1.0, (val) {
              setState(() {
                clip.chromaKeySpill = val;
              });
              _pushHistoryState();
            }),
          ]
        ],
      ),
    );
  }

  Widget _buildAudioPanel() {
    final stockTracks = [
      {'name': 'Upbeat Vibe', 'dummy': 'stock_upbeat.mp3'},
      {'name': 'Chill HipHop', 'dummy': 'stock_chill.mp3'},
      {'name': 'Cinematic Epic', 'dummy': 'stock_cinematic.mp3'},
      {'name': 'Acoustic Folk', 'dummy': 'stock_acoustic.mp3'},
    ];

    return _buildPanelWrapper(
      title: "Add Background Music",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickAndAddAudio,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text("Import from Storage"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade400,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text("Stock Royalty-Free Library:", style: TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: stockTracks.length,
              itemBuilder: (context, index) {
                final track = stockTracks[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF1C1C1E),
                    label: Text(track['name']!),
                    avatar: const Icon(Icons.music_video_rounded, color: Colors.tealAccent, size: 14),
                    onPressed: () => _addStockMusic(track['name']!, track['dummy']!),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceoverPanel() {
    final recTimeStr = "${_recordingDurationSec ~/ 60}:${(_recordingDurationSec % 60).toString().padLeft(2, '0')}";
    return _buildPanelWrapper(
      title: "Voiceover Recording",
      child: Center(
        child: Column(
          children: [
            Text(
              _isRecording ? "Recording... $recTimeStr" : "Tap Microphone to Start",
              style: TextStyle(
                color: _isRecording ? Colors.redAccent : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.redAccent : Colors.tealAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.teal).withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 3,
                    )
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 32,
                  color: Colors.black,
                ),
              ),
            ),
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Transcribing: \"$_recognizedText\"",
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              )
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTTSPanel() {
    return _buildPanelWrapper(
      title: "AI Narrator - Text-to-Speech",
      child: Column(
        children: [
          TextField(
            controller: _ttsController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: "Type text for AI narration generator...",
              hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _activePanel = 'none'),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _synthesizeTTS,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text("Generate Audio"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedPanel() {
    final clip = _selectedClip!;
    return _buildPanelWrapper(
      title: "Clip Speed: ${clip.speed}x",
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: clip.speed,
              min: 0.25,
              max: 4.0,
              divisions: 15,
              activeColor: Colors.tealAccent,
              inactiveColor: Colors.white24,
              onChanged: (val) {
                setState(() {
                  _updateClipSpeed(val);
                });
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _updateClipSpeed(1.0);
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade400,
              foregroundColor: Colors.black,
            ),
            child: const Text("Reset (1.0x)"),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumePanel() {
    final clip = _selectedClip!;
    return _buildPanelWrapper(
      title: "Clip Volume: ${(clip.volume * 100).toInt()}%",
      child: Slider(
        value: clip.volume,
        min: 0.0,
        max: 2.0,
        activeColor: Colors.tealAccent,
        inactiveColor: Colors.white24,
        onChanged: (val) {
          setState(() {
            _updateClipVolume(val);
          });
        },
      ),
    );
  }

  Widget _buildFiltersPanel() {
    final clip = _selectedClip!;
    final activeFilter = clip.effects.firstWhere(
      (e) => e.type == 'lut_filter',
      orElse: () => FilterEffect(id: '', filterName: 'none'),
    ) as FilterEffect;

    final filters = [
      {'name': 'Original', 'id': 'none'},
      {'name': 'Sepia', 'id': 'sepia'},
      {'name': 'Mono', 'id': 'grayscale'},
      {'name': 'Vintage', 'id': 'vintage'},
      {'name': 'Cool', 'id': 'cool'},
      {'name': 'Warm', 'id': 'warm'},
    ];

    return _buildPanelWrapper(
      title: "Apply Color Filter LUT",
      child: SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          itemBuilder: (context, index) {
            final filter = filters[index];
            final isSelected = activeFilter.filterName == filter['id'];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(filter['name']!),
                selected: isSelected,
                selectedColor: Colors.tealAccent.shade400,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                backgroundColor: const Color(0xFF161618),
                onSelected: (_) {
                  setState(() {
                    _applyFilter(filter['id']!);
                  });
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAdjustPanel() {
    final clip = _selectedClip!;
    final adjust = _getOrAddAdjustmentEffect(clip);

    return _buildPanelWrapper(
      title: "Color Adjustments",
      child: Column(
        children: [
          _buildAdjustmentSlider("Brightness", adjust.brightness, -1.0, 1.0, (val) {
            _updateAdjustment('brightness', val);
          }),
          _buildAdjustmentSlider("Contrast", adjust.contrast, 0.0, 2.0, (val) {
            _updateAdjustment('contrast', val);
          }),
          _buildAdjustmentSlider("Saturation", adjust.saturation, 0.0, 2.0, (val) {
            _updateAdjustment('saturation', val);
          }),
        ],
      ),
    );
  }

  Widget _buildAdjustmentSlider(
      String label, double val, double min, double max, ValueChanged<double> onChange) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70))),
        Expanded(
          child: Slider(
            value: val,
            min: min,
            max: max,
            activeColor: Colors.tealAccent,
            inactiveColor: Colors.white24,
            onChanged: onChange,
          ),
        ),
        Text(val.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  Widget _buildStickersPanel() {
    final emojis = ["😀", "🔥", "✨", "🎬", "💯", "🎉", "💀", "❤️", "👍", "🚀", "👑", "👀"];
    return _buildPanelWrapper(
      title: "Tap to Add Sticker Overlay",
      child: SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: emojis.length,
          itemBuilder: (context, index) {
            final emoji = emojis[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: GestureDetector(
                onTap: () {
                  _addStickerOverlay(emoji);
                  setState(() => _activePanel = 'none');
                },
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTransitionsPanel() {
    final clip = _selectedClip!;
    final transitionOptions = [
      {'name': 'None', 'id': 'none'},
      {'name': 'Fade Cross', 'id': 'fade'},
      {'name': 'Zoom Cut', 'id': 'zoom'},
      {'name': 'Slide Left', 'id': 'slide'},
    ];

    return _buildPanelWrapper(
      title: "Transition to Next Clip",
      child: SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: transitionOptions.length,
          itemBuilder: (context, index) {
            final t = transitionOptions[index];
            final isSelected = clip.transitionType == t['id'];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ChoiceChip(
                label: Text(t['name']!),
                selected: isSelected,
                selectedColor: Colors.tealAccent.shade700,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                backgroundColor: const Color(0xFF161618),
                onSelected: (_) {
                  setState(() {
                    clip.transitionType = t['id']!;
                  });
                  _pushHistoryState();
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPanelWrapper({required String title, required Widget child}) {
    return Container(
      color: const Color(0xFF161618),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent, fontSize: 13)),
              GestureDetector(
                onTap: () => setState(() => _activePanel = 'none'),
                child: const Icon(Icons.close, size: 18, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildToolBtn({required IconData icon, required String label, Color? color, VoidCallback? onTap}) {
    final isEnabled = onTap != null;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.3,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color ?? Colors.white),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(int totalDuration) {
    final double timelineWidth = totalDuration * 0.15 * _zoomScale;

    return Container(
      color: const Color(0xFF131314),
      child: Column(
        children: [
          Container(
            height: 30,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: timelineWidth + 500,
                child: Stack(
                  children: List.generate((totalDuration ~/ 1000) + 5, (index) {
                    final timeMs = index * 1000;
                    final leftPos = timeMs * 0.15 * _zoomScale;
                    return Positioned(
                      left: leftPos,
                      bottom: 4,
                      child: Text(
                        "${index}s",
                        style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: timelineWidth + constraints.maxWidth,
                        child: Column(
                          children: [
                            _buildTrackLane(TrackType.mainVideo),
                            _buildTrackLane(TrackType.text),
                            _buildTrackLane(TrackType.audio),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1.5,
                        color: Colors.redAccent,
                      ),
                    ),
                    GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        final double dragDelta = details.primaryDelta ?? 0.0;
                        final double scaleFactor = 0.15 * _zoomScale;
                        final int timeDeltaMs = -(dragDelta / scaleFactor).toInt();
                        _seekTo(_currentTimeMs + timeDeltaMs);
                      },
                      child: Container(
                        height: 30,
                        color: Colors.transparent,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackLane(TrackType type) {
    final track = _project.tracks.firstWhere(
      (t) => t.type == type,
      orElse: () => Track(id: '', type: type, zOrder: 0, clips: []),
    );

    String label;
    IconData icon;
    Color color;
    switch (type) {
      case TrackType.mainVideo:
        label = "Video Track";
        icon = Icons.movie_creation_outlined;
        color = Colors.teal.shade800.withOpacity(0.5);
        break;
      case TrackType.text:
        label = "Text Track";
        icon = Icons.text_fields;
        color = Colors.purple.shade900.withOpacity(0.5);
        break;
      case TrackType.audio:
        label = "Audio Track";
        icon = Icons.music_note;
        color = Colors.blue.shade900.withOpacity(0.5);
        break;
      default:
        label = "Overlay";
        icon = Icons.layers_outlined;
        color = Colors.grey.shade900;
    }

    return Container(
      height: 65,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 8,
            child: Row(
              children: [
                Icon(icon, color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          ...track.clips.map((clip) {
            final double left = clip.startInTimelineMs * 0.15 * _zoomScale;
            final double width = clip.durationMs * 0.15 * _zoomScale;
            final isSelected = _selectedClip?.id == clip.id;
            
            final clipName = clip.sourcePath != null
                ? clip.sourcePath!.split(Platform.pathSeparator).last
                : clip.textContent ?? 'Text Clip';

            return Positioned(
              left: left,
              top: 24,
              bottom: 8,
              width: width,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedClip = null;
                      _selectedTrack = null;
                      _activePanel = 'none';
                    } else {
                      _selectedClip = clip;
                      _selectedTrack = track;
                    }
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.tealAccent : Colors.tealAccent.withOpacity(0.2),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (type == TrackType.audio)
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.35,
                            child: _buildProceduralWaveform(clip),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          clipName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                      
                      if (clip.keyframes.isNotEmpty)
                        ...clip.keyframes.map((k) {
                          final double kLeft = k.timeOffsetMs * 0.15 * _zoomScale;
                          return Positioned(
                            left: kLeft,
                            top: 0,
                            bottom: 0,
                            child: const Center(
                              child: Icon(Icons.diamond_rounded, color: Colors.redAccent, size: 10),
                            ),
                          );
                        }),

                      if (type == TrackType.audio && clip.beats.isNotEmpty)
                        ...clip.beats.map((beatMs) {
                          final double markerLeft = beatMs * 0.15 * _zoomScale;
                          return Positioned(
                            left: markerLeft,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 2.5,
                              color: Colors.yellowAccent,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProceduralWaveform(TimelineClip clip) {
    final int seed = clip.id.hashCode;
    final Random random = Random(seed);
    final List<int> barHeights = List.generate(40, (_) => random.nextInt(32) + 4);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: barHeights.map((h) {
            return Container(
              width: max(1.5, constraints.maxWidth / 45),
              height: h.toDouble(),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// Shape Mask Path Clipper
class MaskClipper extends CustomClipper<Path> {
  final String maskType;
  final double size; // 0.0 to 2.0
  final double feather;

  MaskClipper(this.maskType, this.size, this.feather);

  @override
  Path getClip(Size sizeRect) {
    final Path path = Path();
    if (maskType == 'circle') {
      final radius = sizeRect.width * size * 0.4;
      path.addOval(Rect.fromCircle(
        center: Offset(sizeRect.width / 2, sizeRect.height / 2),
        radius: radius.clamp(5.0, sizeRect.width * 2),
      ));
    } else if (maskType == 'rectangle') {
      final w = sizeRect.width * size;
      final h = sizeRect.height * size;
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(sizeRect.width / 2, sizeRect.height / 2),
          width: w.clamp(10.0, sizeRect.width * 2),
          height: h.clamp(10.0, sizeRect.height * 2),
        ),
        const Radius.circular(16),
      ));
    } else if (maskType == 'linear') {
      final cutX = sizeRect.width * size * 0.5;
      path.moveTo(0, 0);
      path.lineTo(cutX, 0);
      path.lineTo(cutX, sizeRect.height);
      path.lineTo(0, sizeRect.height);
      path.close();
    } else if (maskType == 'mirror') {
      final width = sizeRect.width * size * 0.5;
      final left = (sizeRect.width - width) / 2;
      path.moveTo(left, 0);
      path.lineTo(left + width, 0);
      path.lineTo(left + width, sizeRect.height);
      path.lineTo(left, sizeRect.height);
      path.close();
    } else {
      path.addRect(Rect.fromLTWH(0, 0, sizeRect.width, sizeRect.height));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant MaskClipper oldClipper) {
    return oldClipper.maskType != maskType || oldClipper.size != size || oldClipper.feather != feather;
  }
}
