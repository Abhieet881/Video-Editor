import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/video_editor_models.dart';
import '../services/editor_theme.dart';

class ExportScreen extends StatefulWidget {
  final Project project;
  const ExportScreen({super.key, required this.project});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String _selectedRes = '1080p';
  String _selectedFps = '30fps';
  String _selectedBitrate = 'Medium';

  bool _isRendering = false;
  double _renderProgress = 0.0;
  String _statusMessage = "Preparing render...";
  String? _exportedFilePath;

  // FFmpeg Session tracker to allow cancellation
  dynamic _ffmpegSession;

  int _calculateTotalDuration() {
    int total = 0;
    for (var track in widget.project.tracks) {
      for (var clip in track.clips) {
        final end = clip.startInTimelineMs + clip.durationMs;
        if (end > total) total = end;
      }
    }
    return total;
  }

  double _getEstimatedSizeMb() {
    final int durationMs = _calculateTotalDuration();
    final double seconds = durationMs / 1000.0;

    double baseBitrateMbps = 6.0; // Medium
    if (_selectedBitrate == 'Low') baseBitrateMbps = 2.5;
    if (_selectedBitrate == 'High') baseBitrateMbps = 15.0;

    double resMultiplier = 1.0;
    if (_selectedRes == '720p') resMultiplier = 0.55;
    if (_selectedRes == '4K') resMultiplier = 3.0;

    double fpsMultiplier = 1.0;
    if (_selectedFps == '24fps') fpsMultiplier = 0.9;
    if (_selectedFps == '60fps') fpsMultiplier = 1.4;

    final double totalBitrateMbps = baseBitrateMbps * resMultiplier * fpsMultiplier;
    return (seconds * totalBitrateMbps) / 8.0;
  }

  Map<String, int> _getTargetDimensions() {
    int w = 1080;
    int h = 1920;

    if (_selectedRes == '720p') {
      w = 720;
      h = 1280;
    } else if (_selectedRes == '4K') {
      w = 2160;
      h = 3840;
    }

    if (widget.project.aspectRatio == EditorAspectRatio.ratio16to9) {
      return {'width': h, 'height': w};
    } else if (widget.project.aspectRatio == EditorAspectRatio.ratio1to1) {
      return {'width': w, 'height': w};
    } else if (widget.project.aspectRatio == EditorAspectRatio.ratio4to5) {
      return {'width': w, 'height': (w * 1.25).toInt()};
    }
    return {'width': w, 'height': h}; // Default 9:16
  }

  String _buildFFmpegExportCommand(String outputPath, int targetW, int targetH) {
    final mainTrack = widget.project.tracks.firstWhere(
      (t) => t.type == TrackType.mainVideo,
      orElse: () => Track(id: '', type: TrackType.mainVideo, zOrder: 0, clips: []),
    );

    final audioTrack = widget.project.tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () => Track(id: '', type: TrackType.audio, zOrder: -1, clips: []),
    );

    final textTrack = widget.project.tracks.firstWhere(
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
        String filter = '[$inputIdx:v]trim=start=$startSec:duration=$durationSec,setpts=PTS-STARTPTS';
        if (clip.transform.cropMinX != 0.0 || clip.transform.cropMinY != 0.0 ||
            clip.transform.cropMaxX != 1.0 || clip.transform.cropMaxY != 1.0) {
          final cw = clip.transform.cropMaxX - clip.transform.cropMinX;
          final ch = clip.transform.cropMaxY - clip.transform.cropMinY;
          final cx = clip.transform.cropMinX;
          final cy = clip.transform.cropMinY;
          filter += ',crop=$cw*in_w:$ch*in_h:$cx*in_w:$cy*in_h';
        }
        filter += ',scale=${targetW}:${targetH}:force_original_aspect_ratio=decrease,pad=${targetW}:${targetH}:(ow-iw)/2:(oh-ih)/2:black';

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

        if (clip.transform.rotation != 0.0) {
          final rad = clip.transform.rotation * 3.14159265 / 180.0;
          filter += ',rotate=$rad:fillcolor=black';
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

    final int fpsVal = int.parse(_selectedFps.replaceAll('fps', ''));

    return '$inputArgs $complexFilterArg $mapArgs -r $fpsVal -c:v libx264 -preset ultrafast -c:a aac -shortest "$outputPath"';
  }

  Future<void> _exportVideo() async {
    setState(() {
      _isRendering = true;
      _renderProgress = 0.0;
      _statusMessage = "Starting H.264 compile...";
    });

    final totalDurMs = _calculateTotalDuration();
    FFmpegKitConfig.enableStatisticsCallback((stats) {
      if (totalDurMs > 0) {
        final double currentProgress = (stats.getTime() / totalDurMs) * 100;
        setState(() {
          _renderProgress = currentProgress.clamp(0.0, 100.0);
          _statusMessage = "Encoding frames: ${_renderProgress.toStringAsFixed(0)}%";
        });
      }
    });

    try {
      final dims = _getTargetDimensions();
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final cmd = _buildFFmpegExportCommand(tempPath, dims['width']!, dims['height']!);
      
      _ffmpegSession = await FFmpegKit.execute(cmd);
      final returnCode = await _ffmpegSession.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // Save to public gallery
        await Gal.putVideo(tempPath, album: 'MyVideoEditor');
        
        setState(() {
          _isRendering = false;
          _exportedFilePath = tempPath;
          _statusMessage = "Saved to Gallery! 🎉";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Masterpiece successfully saved to Gallery!"), backgroundColor: EditorTheme.playhead),
        );
      } else if (ReturnCode.isCancel(returnCode)) {
        setState(() {
          _isRendering = false;
          _statusMessage = "Export cancelled.";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Export cancelled by user"), backgroundColor: Colors.amber),
        );
      } else {
        setState(() {
          _isRendering = false;
          _statusMessage = "Encoding failed.";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("FFmpeg compilation failed"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      setState(() {
        _isRendering = false;
        _statusMessage = "Error occurred.";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Render failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _cancelExport() {
    if (_ffmpegSession != null) {
      FFmpegKit.cancel(_ffmpegSession.getSessionId());
    }
  }

  void _shareExportedFile() async {
    final path = _exportedFilePath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please export the video first before sharing!"), backgroundColor: Colors.amber),
      );
      return;
    }
    // Launch share sheet using share_plus
    await Share.shareXFiles([XFile(path)], text: 'Check out my video edited in MyVideoEditor!');
  }

  void _showSettingPicker(String type, List<String> options, String current, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorTheme.buttonFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: EditorTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  "Select $type",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: EditorTheme.textPrimary),
                ),
              ),
              const Divider(color: EditorTheme.border, height: 1),
              ...options.map((opt) {
                final isSelected = opt == current;
                return ListTile(
                  title: Text(opt, style: TextStyle(color: isSelected ? EditorTheme.playhead : EditorTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: EditorTheme.playhead) : null,
                  onTap: () {
                    onSelect(opt);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int durationMs = _calculateTotalDuration();
    final double durationSec = durationMs / 1000.0;
    final double estimatedSizeMb = _getEstimatedSizeMb();
    final double ratioValue = widget.project.aspectRatio == EditorAspectRatio.ratio16to9 
        ? 16/9 
        : widget.project.aspectRatio == EditorAspectRatio.ratio1to1 
            ? 1/1 
            : widget.project.aspectRatio == EditorAspectRatio.ratio4to5 
                ? 4/5 
                : 9/16;

    final hasThumbnail = widget.project.thumbnailPath != null && File(widget.project.thumbnailPath!).existsSync();

    return Scaffold(
      backgroundColor: EditorTheme.background,
      appBar: AppBar(
        backgroundColor: EditorTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: EditorTheme.textPrimary, size: 20),
          onPressed: _isRendering ? null : () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          "Export",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: EditorTheme.textPrimary),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: EditorTheme.border, height: 1, thickness: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Cover frame Preview Card
              Center(
                child: Container(
                  height: 180,
                  width: 180 * ratioValue,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: EditorTheme.border, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasThumbnail
                      ? Image.file(File(widget.project.thumbnailPath!), fit: BoxFit.cover)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF141416), Color(0xFF262628)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.video_collection_outlined, color: EditorTheme.textSecondary, size: 36),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              // Export Settings Table Card
              Container(
                decoration: BoxDecoration(
                  color: EditorTheme.buttonFill,
                  border: Border.all(color: EditorTheme.buttonBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _buildSettingsRow(
                      label: "Resolution",
                      value: _selectedRes,
                      onTap: () => _showSettingPicker(
                        "Resolution", 
                        ['720p', '1080p', '4K'], 
                        _selectedRes, 
                        (val) => setState(() => _selectedRes = val)
                      ),
                    ),
                    const Divider(color: EditorTheme.border, height: 1),
                    _buildSettingsRow(
                      label: "Frame rate",
                      value: _selectedFps,
                      onTap: () => _showSettingPicker(
                        "Frame rate", 
                        ['24fps', '30fps', '60fps'], 
                        _selectedFps, 
                        (val) => setState(() => _selectedFps = val)
                      ),
                    ),
                    const Divider(color: EditorTheme.border, height: 1),
                    _buildSettingsRow(
                      label: "Bitrate",
                      value: _selectedBitrate,
                      onTap: () => _showSettingPicker(
                        "Bitrate", 
                        ['Low', 'Medium', 'High'], 
                        _selectedBitrate, 
                        (val) => setState(() => _selectedBitrate = val)
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Live calculated stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Est. size: ~${estimatedSizeMb.toStringAsFixed(1)} MB",
                    style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
                  ),
                  Text(
                    "Duration: ${durationSec.toStringAsFixed(1)}s",
                    style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // Rendering status panel / Primary Button
              if (_isRendering) ...[
                Text(_statusMessage, style: const TextStyle(color: EditorTheme.playhead, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _renderProgress / 100.0,
                  color: EditorTheme.playhead,
                  backgroundColor: EditorTheme.buttonBorder,
                  minHeight: 6,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _cancelExport,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.red.shade900.withOpacity(0.3),
                      side: BorderSide(color: Colors.red.shade700, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Cancel Export", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _exportVideo,
                    style: EditorTheme.getButtonStyle(isPrimary: true),
                    child: const Text("Save to gallery", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              const Divider(color: EditorTheme.border),
              const SizedBox(height: 16),
              const Text("Share finished video directly:", style: TextStyle(color: EditorTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              // Social Share Icons row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildShareIcon(Icons.video_library_rounded, "YouTube", const Color(0xFFFF0000)),
                  _buildShareIcon(Icons.camera_alt_rounded, "Instagram", const Color(0xFFE1306C)),
                  _buildShareIcon(Icons.tiktok_rounded, "TikTok", Colors.white),
                  _buildShareIcon(Icons.share_rounded, "Share", EditorTheme.playhead),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsRow({required String label, required String value, required VoidCallback onTap}) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: EditorTheme.playhead, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: EditorTheme.textSecondary, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildShareIcon(IconData icon, String label, Color accentColor) {
    return GestureDetector(
      onTap: _shareExportedFile,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EditorTheme.buttonFill,
              shape: BoxShape.circle,
              border: Border.all(color: EditorTheme.buttonBorder),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
