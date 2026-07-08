import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../models/video_editor_models.dart';
import '../services/project_manager.dart';
import '../services/editor_theme.dart';
import 'editor_screen.dart';

class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  EditorAspectRatio _selectedRatio = EditorAspectRatio.ratio9to16;
  List<File> _availableMedia = [];
  final List<File> _selectedFiles = [];
  bool _isLoadingMedia = true;

  // Caching maps to avoid redundant native calculations
  final Map<String, Duration> _durationCache = {};
  final Map<String, String?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _loadDeviceMedia();
  }

  Future<void> _loadDeviceMedia() async {
    setState(() => _isLoadingMedia = true);
    try {
      final List<File> files = [];
      final List<String> searchDirs = [
        '/sdcard/Download',
        '/sdcard/Movies',
        '/sdcard/Pictures',
        '/sdcard/DCIM',
      ];

      for (final path in searchDirs) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final List<FileSystemEntity> list = dir.listSync(recursive: true);
          for (final entity in list) {
            if (entity is File) {
              final lowerPath = entity.path.toLowerCase();
              if (lowerPath.endsWith('.mp4') ||
                  lowerPath.endsWith('.mov') ||
                  lowerPath.endsWith('.jpg') ||
                  lowerPath.endsWith('.jpeg') ||
                  lowerPath.endsWith('.png')) {
                files.add(entity);
              }
            }
          }
        }
      }

      // Sort files: newer files first
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      setState(() {
        _availableMedia = files;
        _isLoadingMedia = false;
      });
    } catch (e) {
      setState(() => _isLoadingMedia = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error listing media files: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<Duration> _getVideoDuration(File file) async {
    if (_durationCache.containsKey(file.path)) {
      return _durationCache[file.path]!;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      _durationCache[file.path] = duration;
      await controller.dispose();
      return duration;
    } catch (_) {
      await controller.dispose();
      return Duration.zero;
    }
  }

  Future<String?> _getVideoThumbnail(File file) async {
    if (_thumbnailCache.containsKey(file.path)) {
      return _thumbnailCache[file.path];
    }
    try {
      final cacheDir = await getTemporaryDirectory();
      final thumbFile = File('${cacheDir.path}/${file.path.hashCode}.jpg');
      if (await thumbFile.exists()) {
        _thumbnailCache[file.path] = thumbFile.path;
        return thumbFile.path;
      }
      
      // Execute frame extraction command at t = 0.5s using FFmpegKit
      final cmd = '-y -ss 00:00:00.500 -i "${file.path}" -vframes 1 -q:v 4 "${thumbFile.path}"';
      await FFmpegKit.execute(cmd);
      
      if (await thumbFile.exists()) {
        _thumbnailCache[file.path] = thumbFile.path;
        return thumbFile.path;
      }
    } catch (_) {}
    _thumbnailCache[file.path] = null;
    return null;
  }

  void _toggleSelection(File file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  String _formatDuration(Duration d) {
    final sec = d.inSeconds % 60;
    final min = d.inMinutes;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _startEditing() async {
    if (_selectedFiles.isEmpty) return;

    // Show loading indicator dialog during import metadata probing
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: EditorTheme.playhead),
      ),
    );

    try {
      final List<TimelineClip> mainTrackClips = [];
      int currentTimelineOffset = 0;

      for (var i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        final bool isVideo = file.path.toLowerCase().endsWith('.mp4') || file.path.toLowerCase().endsWith('.mov');
        
        int durationMs = 3000; // default 3s for static image files
        if (isVideo) {
          final duration = await _getVideoDuration(file);
          if (duration.inMilliseconds > 0) {
            durationMs = duration.inMilliseconds;
          }
        }

        mainTrackClips.add(
          TimelineClip(
            id: 'clip_${DateTime.now().millisecondsSinceEpoch}_$i',
            sourcePath: file.path,
            startInTimelineMs: currentTimelineOffset,
            durationMs: durationMs,
            startInSourceMs: 0,
            transform: ClipTransform(),
            effects: [],
          ),
        );
        currentTimelineOffset += durationMs;
      }

      final project = Project(
        id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Project ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        aspectRatio: _selectedRatio,
        tracks: [
          Track(
            id: 'track_main_video',
            type: TrackType.mainVideo,
            zOrder: 0,
            clips: mainTrackClips,
          ),
          Track(
            id: 'track_text_1',
            type: TrackType.text,
            zOrder: 1,
            clips: [],
          ),
          Track(
            id: 'track_audio_1',
            type: TrackType.audio,
            zOrder: -1,
            clips: [],
          ),
        ],
      );

      // Close loading dialog
      Navigator.of(context).pop();

      // Save draft state
      await ProjectManager().saveProject(project);

      // Push and replace Editor screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => EditorScreen(project: project),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error preparing project metadata: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSelection = _selectedFiles.isNotEmpty;

    return Scaffold(
      backgroundColor: EditorTheme.background, // Premiere true black
      appBar: AppBar(
        backgroundColor: EditorTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: EditorTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          "Select media",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: EditorTheme.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: ElevatedButton(
              onPressed: hasSelection ? _startEditing : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTheme.playhead,
                foregroundColor: Colors.black,
                disabledBackgroundColor: EditorTheme.textMuted,
                disabledForegroundColor: Colors.black38,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              child: const Text("Next", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: EditorTheme.border, height: 1, thickness: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Aspect Ratio selector pills
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                children: EditorAspectRatio.values.map((ratio) {
                  final bool isSelected = _selectedRatio == ratio;
                  String label = ratio.name.split('.').last.replaceAll('ratio', '').replaceAll('to', ':');

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.black : EditorTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: EditorTheme.playhead,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : EditorTheme.buttonBorder,
                        width: 1.0,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedRatio = ratio);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: EditorTheme.border, height: 1),
            // 3-column gallery grid
            Expanded(
              child: _isLoadingMedia
                  ? const Center(child: CircularProgressIndicator(color: EditorTheme.playhead))
                  : _availableMedia.isEmpty
                      ? const Center(
                          child: Text(
                            "No media files found in local storage\n(Add mp4/jpg files to Download folder)",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: EditorTheme.textSecondary, fontSize: 13),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1.0, // Square thumbnails
                          ),
                          itemCount: _availableMedia.length,
                          itemBuilder: (context, index) {
                            final File file = _availableMedia[index];
                            final String path = file.path.toLowerCase();
                            final bool isVideo = path.endsWith('.mp4') || path.endsWith('.mov');
                            final bool isSelected = _selectedFiles.contains(file);
                            final int selectionIndex = _selectedFiles.indexOf(file) + 1;

                            return GestureDetector(
                              onTap: () => _toggleSelection(file),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected ? EditorTheme.playhead : Colors.transparent,
                                    width: 2.0,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Video thumbnail generator or direct image renderer
                                      isVideo
                                          ? FutureBuilder<String?>(
                                              future: _getVideoThumbnail(file),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData && snapshot.data != null) {
                                                  return Image.file(File(snapshot.data!), fit: BoxFit.cover);
                                                }
                                                return Container(
                                                  color: EditorTheme.buttonFill,
                                                  child: const Center(
                                                    child: Icon(Icons.movie_creation_outlined, color: EditorTheme.textSecondary, size: 24),
                                                  ),
                                                );
                                              },
                                            )
                                          : Image.file(file, fit: BoxFit.cover),
                                      // Video Duration indicator
                                      if (isVideo)
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: FutureBuilder<Duration>(
                                            future: _getVideoDuration(file),
                                            builder: (context, snapshot) {
                                              final Duration dur = snapshot.data ?? Duration.zero;
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.7),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 10),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      _formatDuration(dur),
                                                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      // Selection badge
                                      if (isSelected)
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: const BoxDecoration(
                                              color: EditorTheme.playhead,
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              "$selectionIndex",
                                              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Bottom Info Bar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              decoration: const BoxDecoration(
                color: EditorTheme.buttonFill,
                border: Border(top: BorderSide(color: EditorTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${_selectedFiles.length} selected",
                    style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    "Photos & videos",
                    style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
