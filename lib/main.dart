import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Video Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        primaryColor: Colors.tealAccent.shade400,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
          primary: Colors.tealAccent.shade400,
          secondary: Colors.cyanAccent.shade400,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const VideoPickerScreen(),
    );
  }
}

//--------------------//
//VIDEO PICKER SCREEN //
//--------------------//
class VideoPickerScreen extends StatefulWidget {
  const VideoPickerScreen({super.key});

  @override
  State<VideoPickerScreen> createState() => _VideoPickerScreenState();
}

class _VideoPickerScreenState extends State<VideoPickerScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (BuildContext context) => VideoTrimScreen(file: file),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error picking video: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Colors.teal.shade900.withOpacity(0.4),
              Colors.black,
            ],
            center: const Alignment(0, -0.3),
            radius: 1.2,
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.tealAccent.shade400.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent.shade400.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Icon(
                      Icons.movie_creation_outlined,
                      size: 45,
                      color: Colors.tealAccent.shade400,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    "AI Video Editor",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.tealAccent.shade400.withOpacity(0.3),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Fast, lightweight, and hardware-accelerated video trimming",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 60),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _pickVideo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent.shade400,
                        foregroundColor: Colors.black,
                        elevation: 6,
                        shadowColor: Colors.tealAccent.shade400.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isPicking
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.file_upload_outlined, size: 24),
                                SizedBox(width: 12),
                                Text(
                                  "Select Video File",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

//--------------------//
// VIDEO TRIM SCREEN  //
//--------------------//
class VideoTrimScreen extends StatefulWidget {
  final File file;
  const VideoTrimScreen({super.key, required this.file});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isExporting = false;

  // Selected range in milliseconds
  double _startValue = 0.0;
  double _endValue = 1.0;
  double _videoDurationMs = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _controller = VideoPlayerController.file(widget.file);
    try {
      await _controller!.initialize();
      _videoDurationMs = _controller!.value.duration.inMilliseconds.toDouble();
      _startValue = 0.0;
      _endValue = _videoDurationMs;

      _controller!.addListener(_playerListener);
      setState(() {
        _initialized = true;
      });
      _controller!.play();
    } catch (e) {
      debugPrint("Error initializing video player: $e");
      setState(() {
        _hasError = true;
      });
    }
  }

  void _playerListener() {
    if (!mounted || _controller == null) return;
    final currentPos = _controller!.value.position.inMilliseconds.toDouble();

    // Loop logic to preview only selected range
    if (currentPos >= _endValue) {
      _controller!.seekTo(Duration(milliseconds: _startValue.toInt()));
    } else if (currentPos < _startValue) {
      _controller!.seekTo(Duration(milliseconds: _startValue.toInt()));
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_playerListener);
    _controller?.dispose();
    super.dispose();
  }

  String _formatMs(double milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _exportTrimmedVideo() async {
    if (_controller == null || _isExporting) return;

    setState(() {
      _isExporting = true;
    });
    _controller!.pause();

    try {
      final startSeconds = _startValue / 1000.0;
      final endSeconds = _endValue / 1000.0;
      final durationSeconds = endSeconds - startSeconds;

      final tempDir = await getTemporaryDirectory();
      final outputFileName = "trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final outputPath = "${tempDir.path}/$outputFileName";

      // 1. Fast trim utilizing stream copy (-c copy)
      final command = '-y -ss $startSeconds -i "${widget.file.path}" -t $durationSeconds -c copy "$outputPath"';
      debugPrint("Executing FFmpeg command: $command");

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        await _saveToGalleryAndShowResult(outputPath);
      } else {
        // 2. Fallback to full re-encode if keyframe copy fails
        debugPrint("Fast copy failed, falling back to full re-encode...");
        final encodeCommand = '-y -ss $startSeconds -i "${widget.file.path}" -t $durationSeconds -preset ultrafast -c:v libx264 -c:a aac "$outputPath"';
        final encodeSession = await FFmpegKit.execute(encodeCommand);
        final encodeReturnCode = await encodeSession.getReturnCode();

        if (ReturnCode.isSuccess(encodeReturnCode)) {
          await _saveToGalleryAndShowResult(outputPath);
        } else {
          throw Exception("FFmpeg processing failed.");
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Export failed: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _saveToGalleryAndShowResult(String tempPath) async {
    try {
      // 1. Request access permissions
      bool hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess(toAlbum: true);
      }

      if (!hasAccess) {
        throw Exception("Access to photo library/gallery was denied by the user. Please enable permissions in settings.");
      }

      // 2. Save video to public storage under custom album (Movies/AI_Video_Editor)
      const albumName = 'AI_Video_Editor';
      await Gal.putVideo(tempPath, album: albumName);

      // 3. Delete intermediate temp file from cache
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }

      if (!mounted) return;

      // 4. Show success SnackBar with "View" action
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Video saved to Gallery under Movies/AI_Video_Editor/"),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: "VIEW",
            textColor: Colors.tealAccent,
            onPressed: () async {
              try {
                await Gal.open();
              } catch (e) {
                debugPrint("Error opening gallery: $e");
              }
            },
          ),
        ),
      );

      // 5. Show Success Dialog
      _showSuccessDialog('Gallery (Movies/AI_Video_Editor)');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save to Gallery: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(String displayPath) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141414),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.tealAccent, size: 28),
              SizedBox(width: 10),
              Text("Export Complete"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Your trimmed video is saved successfully:",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade900),
                ),
                child: Text(
                  displayPath,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.tealAccent,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await Gal.open();
                } catch (e) {
                  debugPrint("Error opening gallery: $e");
                }
              },
              child: const Text("Open Gallery"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss Dialog
                Navigator.of(context).pop(); // Go back to picker
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                foregroundColor: Colors.black,
              ),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
              const SizedBox(height: 20),
              const Text("Could not load the selected video"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Go Back"),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Loading video details..."),
            ],
          ),
        ),
      );
    }

    final double currentPos = _controller!.value.position.inMilliseconds.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Trim Video"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Video Preview Box
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade900, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                        // Play/Pause Overlay
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_controller!.value.isPlaying) {
                                _controller!.pause();
                              } else {
                                _controller!.play();
                              }
                            });
                          },
                          child: AnimatedOpacity(
                            opacity: _controller!.value.isPlaying ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              width: 65,
                              height: 65,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.tealAccent.shade400, width: 1.5),
                              ),
                              child: Icon(
                                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.tealAccent.shade400,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Controls and Slider Section
                Container(
                  color: const Color(0xFF0F0F0F),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Range details / positions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "CURRENT POSITION",
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatMs(currentPos),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "TRIM RANGE",
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${_formatMs(_startValue)} - ${_formatMs(_endValue)}",
                                style: TextStyle(color: Colors.tealAccent.shade400, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Premium Custom Range Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.tealAccent.shade400,
                          inactiveTrackColor: Colors.grey.shade800,
                          trackHeight: 6.0,
                          rangeThumbShape: const RoundRangeSliderThumbShape(
                            enabledThumbRadius: 10.0,
                            elevation: 4.0,
                          ),
                          overlayColor: Colors.tealAccent.withOpacity(0.15),
                        ),
                        child: RangeSlider(
                          values: RangeValues(_startValue, _endValue),
                          min: 0.0,
                          max: _videoDurationMs,
                          onChanged: (RangeValues values) {
                            setState(() {
                              // Ensure trim duration is at least 500ms
                              if (values.end - values.start >= 500) {
                                _startValue = values.start;
                                _endValue = values.end;
                              }
                            });
                            // Seek to start position on range change to show preview
                            _controller!.seekTo(Duration(milliseconds: _startValue.toInt()));
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Execution Action Bar
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                } else {
                                  _controller!.play();
                                }
                              });
                            },
                            icon: Icon(
                              _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _exportTrimmedVideo,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.tealAccent.shade400,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 4,
                                ),
                                child: const Text(
                                  "Trim & Save Video",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Exporting Overlay
          if (_isExporting)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.tealAccent),
                    const SizedBox(height: 24),
                    const Text(
                      "Processing video...",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Trimming with FFmpeg",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
