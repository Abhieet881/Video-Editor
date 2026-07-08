import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/video_editor_models.dart';
import '../services/project_manager.dart';
import 'editor_screen.dart';

class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  EditorAspectRatio _selectedRatio = EditorAspectRatio.ratio9to16;
  final List<File> _selectedFiles = [];
  bool _isPicking = false;

  Future<void> _pickMedia() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          _selectedFiles.addAll(
            result.paths.where((path) => path != null).map((path) => File(path!)),
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking media: $e"), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _isPicking = false);
    }
  }

  void _removeMedia(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _startEditing() {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select at least one video to start editing"),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // Generate a new Project model
    final List<TimelineClip> mainTrackClips = [];
    int currentTimelineOffset = 0;

    for (var i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      // Assume a default duration of 5 seconds (5000ms) for placeholder/indexing
      // In a real app, we will probe the video duration (done in Phase 4/5)
      const defaultDuration = 5000;
      
      mainTrackClips.add(
        TimelineClip(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}_$i',
          sourcePath: file.path,
          startInTimelineMs: currentTimelineOffset,
          durationMs: defaultDuration,
          startInSourceMs: 0,
          transform: ClipTransform(),
          effects: [],
        ),
      );
      currentTimelineOffset += defaultDuration;
    }

    final project = Project(
      id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Project ${DateTime.now().hour}:${DateTime.now().minute}',
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

    // Save project automatically to drafts database
    ProjectManager().saveProject(project);

    // Navigate to Editor
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => EditorScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "New Project Setup",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                "Choose Aspect Ratio",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              // Aspect Ratio Grid Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: EditorAspectRatio.values.map((ratio) {
                  final isSelected = _selectedRatio == ratio;
                  IconData icon;
                  switch (ratio) {
                    case EditorAspectRatio.ratio9to16:
                      icon = Icons.stay_current_portrait_rounded;
                      break;
                    case EditorAspectRatio.ratio16to9:
                      icon = Icons.stay_current_landscape_rounded;
                      break;
                    case EditorAspectRatio.ratio1to1:
                      icon = Icons.crop_square_rounded;
                      break;
                    case EditorAspectRatio.ratio4to5:
                      icon = Icons.portrait_rounded;
                      break;
                  }

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.teal.shade900.withOpacity(0.3) : const Color(0xFF161618),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.tealAccent : Colors.grey.shade900,
                            width: isSelected ? 2 : 1.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() => _selectedRatio = ratio);
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, color: isSelected ? Colors.tealAccent : Colors.grey.shade400, size: 28),
                                const SizedBox(height: 8),
                                Text(
                                  ratio.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.tealAccent : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              const Text(
                "Select Videos",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              // Media Grid / Picker trigger
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161618),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade900, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedFiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_photo_alternate_outlined, size: 50, color: Colors.white38),
                                onPressed: _pickMedia,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No media selected",
                                style: TextStyle(color: Colors.white38, fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _pickMedia,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.tealAccent.shade400,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isPicking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Text("Browse Gallery"),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _selectedFiles.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _selectedFiles.length) {
                              // Extra add button
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.tealAccent.withOpacity(0.3), style: BorderStyle.solid),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.add_rounded, color: Colors.tealAccent),
                                  onPressed: _pickMedia,
                                ),
                              );
                            }

                            final file = _selectedFiles[index];
                            final fileName = file.path.split(Platform.pathSeparator).last;

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.movie_creation_outlined, color: Colors.tealAccent, size: 24),
                                          const SizedBox(height: 4),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                            child: Text(
                                              fileName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Remove button
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeMedia(index),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 24),
              // Start button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _selectedFiles.isEmpty ? null : _startEditing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade400,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    disabledBackgroundColor: Colors.grey.shade800,
                  ),
                  child: const Text(
                    "Start Editing",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
