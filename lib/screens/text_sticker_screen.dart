import 'dart:io';
import 'package:flutter/material.dart';
import '../models/video_editor_models.dart';
import '../services/editor_theme.dart';

class TextStickerScreen extends StatefulWidget {
  final TimelineClip clip;
  final String? backgroundVideoPath; // To show the video clip frame as backdrop if available
  
  const TextStickerScreen({
    super.key,
    required this.clip,
    this.backgroundVideoPath,
  });

  @override
  State<TextStickerScreen> createState() => _TextStickerScreenState();
}

class _TextStickerScreenState extends State<TextStickerScreen> {
  late String _textContent;
  late double _x;
  late double _y;
  late double _scale;
  late String _fontFamily;
  late Color _textColor;
  late String _alignment;
  late String _animationType;

  // Selected sticker if editing a sticker layer
  String? _selectedSticker;

  @override
  void initState() {
    super.initState();
    // Initialize properties from current clip transform
    _textContent = widget.clip.textContent ?? "Double tap to edit";
    _x = widget.clip.transform.x;
    _y = widget.clip.transform.y;
    _scale = widget.clip.transform.scale;
    
    // Attempt to extract properties from effects or use defaults
    _fontFamily = 'monospace';
    _textColor = Colors.white;
    _alignment = 'center';
    _animationType = 'none';

    // If the clip is a sticker, initialize it
    if (widget.clip.id.contains('sticker')) {
      _selectedSticker = widget.clip.textContent;
    }
  }

  void _doubleTapToEdit() {
    if (_selectedSticker != null) return; // stickers don't need text input edit

    final textController = TextEditingController(text: _textContent);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: EditorTheme.buttonFill,
          title: const Text("Edit Text Overlay", style: TextStyle(color: EditorTheme.textPrimary, fontSize: 16)),
          content: TextField(
            controller: textController,
            style: const TextStyle(color: EditorTheme.textPrimary),
            autofocus: true,
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: EditorTheme.border)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: EditorTheme.playhead)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: EditorTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _textContent = textController.text.isNotEmpty ? textController.text : "Text";
                });
                Navigator.pop(context);
              },
              style: EditorTheme.getButtonStyle(isPrimary: true),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  void _openFontPicker() {
    final fonts = ['monospace', 'sans-serif', 'serif', 'cursive'];
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorTheme.buttonFill,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text("Select Font Style", style: TextStyle(fontWeight: FontWeight.bold, color: EditorTheme.textPrimary)),
              ),
              const Divider(color: EditorTheme.border),
              ...fonts.map((font) {
                return ListTile(
                  title: Text(
                    font.toUpperCase(),
                    style: TextStyle(fontFamily: font, color: EditorTheme.textPrimary),
                  ),
                  trailing: _fontFamily == font ? const Icon(Icons.check, color: EditorTheme.playhead) : null,
                  onTap: () {
                    setState(() => _fontFamily = font);
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

  void _openColorPicker() {
    final colors = [
      Colors.white,
      Colors.redAccent,
      Colors.yellowAccent,
      Colors.tealAccent,
      Colors.blueAccent,
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.pinkAccent,
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorTheme.buttonFill,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Select Text Color", style: TextStyle(fontWeight: FontWeight.bold, color: EditorTheme.textPrimary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: colors.map((col) {
                    return GestureDetector(
                      onTap: () {
                        setState(() => _textColor = col);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _textColor == col ? EditorTheme.playhead : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openAlignPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorTheme.buttonFill,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.format_align_left_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Align Left", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  setState(() => _alignment = 'left');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_align_center_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Align Center", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  setState(() => _alignment = 'center');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_align_right_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Align Right", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  setState(() => _alignment = 'right');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openAnimationPicker() {
    final animations = ['none', 'fade', 'slide', 'scale'];
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorTheme.buttonFill,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text("Select Animation Preset", style: TextStyle(fontWeight: FontWeight.bold, color: EditorTheme.textPrimary)),
              ),
              const Divider(color: EditorTheme.border),
              ...animations.map((anim) {
                return ListTile(
                  title: Text(
                    anim.toUpperCase(),
                    style: const TextStyle(color: EditorTheme.textPrimary),
                  ),
                  trailing: _animationType == anim ? const Icon(Icons.check, color: EditorTheme.playhead) : null,
                  onTap: () {
                    setState(() => _animationType = anim);
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

  void _selectSticker(String emoji) {
    setState(() {
      _selectedSticker = emoji;
      _textContent = emoji;
    });
  }

  void _saveAndDone() {
    // Modify values on original clip object to return it
    widget.clip.textContent = _textContent;
    widget.clip.transform.x = _x;
    widget.clip.transform.y = _y;
    widget.clip.transform.scale = _scale;
    
    Navigator.of(context).pop(widget.clip);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> stickerEmojis = [
      '😀', '🔥', '🎉', '❤️', '✨', 
      '⭐', '🎨', '🚀', '🎬', '🎵', 
      '👏', '🎈', '⚡', '💥', '🍿',
    ];

    TextAlign textAlign = TextAlign.center;
    if (_alignment == 'left') textAlign = TextAlign.left;
    if (_alignment == 'right') textAlign = TextAlign.right;

    return Scaffold(
      backgroundColor: EditorTheme.background,
      appBar: AppBar(
        backgroundColor: EditorTheme.background,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel", style: TextStyle(color: EditorTheme.textSecondary, fontWeight: FontWeight.bold)),
        ),
        centerTitle: true,
        title: const Text(
          "Add text",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: EditorTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndDone,
            child: const Text("Done", style: TextStyle(color: EditorTheme.playhead, fontWeight: FontWeight.bold)),
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
            // Preview Area Canvas (Draggable / Resizable Overlay)
            Expanded(
              flex: 4,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EditorTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Video frame/black backdrop
                      Positioned.fill(
                        child: Container(
                          color: const Color(0xFF0F0F10),
                          child: const Center(
                            child: Icon(Icons.movie_filter_outlined, color: Colors.white10, size: 48),
                          ),
                        ),
                      ),
                      // Draggable Text widget on top
                      Positioned(
                        left: 100 + _x,
                        top: 100 + _y,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _x += details.delta.dx;
                              _y += details.delta.dy;
                            });
                          },
                          onDoubleTap: _doubleTapToEdit,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              // Dashed outline simulation
                              border: Border.all(
                                color: EditorTheme.playhead, 
                                style: BorderStyle.solid, 
                                width: 1.0,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Transform.scale(
                              scale: _scale,
                              child: _selectedSticker != null
                                  ? Text(
                                      _selectedSticker!,
                                      style: const TextStyle(fontSize: 48),
                                    )
                                  : Text(
                                      _textContent,
                                      textAlign: textAlign,
                                      style: TextStyle(
                                        color: _textColor,
                                        fontFamily: _fontFamily,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // Scale Slider overlays directly on the canvas bottom
                      Positioned(
                        bottom: 12,
                        left: 20,
                        right: 20,
                        child: Row(
                          children: [
                            const Icon(Icons.text_fields_rounded, color: EditorTheme.textSecondary, size: 14),
                            Expanded(
                              child: Slider(
                                value: _scale,
                                min: 0.5,
                                max: 3.0,
                                activeColor: EditorTheme.playhead,
                                inactiveColor: EditorTheme.buttonBorder,
                                onChanged: (val) {
                                  setState(() => _scale = val);
                                },
                              ),
                            ),
                            const Icon(Icons.text_fields_rounded, color: EditorTheme.textSecondary, size: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Quick action row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: EditorTheme.buttonFill,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQuickActionBtn(icon: Icons.font_download_rounded, label: "Font", onTap: _openFontPicker),
                  _buildQuickActionBtn(icon: Icons.color_lens_rounded, label: "Color", onTap: _openColorPicker),
                  _buildQuickActionBtn(icon: Icons.movie_filter_rounded, label: "Animate", onTap: _openAnimationPicker),
                  _buildQuickActionBtn(icon: Icons.format_align_center_rounded, label: "Align", onTap: _openAlignPicker),
                ],
              ),
            ),
            
            // Stickers Gallery Row
            Container(
              padding: const EdgeInsets.all(16),
              color: EditorTheme.background,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Stickers",
                    style: TextStyle(color: EditorTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  // 5-column grid of emojis
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: stickerEmojis.length,
                    itemBuilder: (context, index) {
                      final emoji = stickerEmojis[index];
                      return GestureDetector(
                        onTap: () => _selectSticker(emoji),
                        child: Container(
                          decoration: BoxDecoration(
                            color: EditorTheme.buttonFill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedSticker == emoji ? EditorTheme.playhead : EditorTheme.buttonBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: EditorTheme.iconPrimary, size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
