import 'package:flutter/material.dart';

class EditorTheme {
  // Premiere Pro inspired color scheme
  static const Color background = Color(0xFF000000); // true black
  static const Color border = Color(0xFF262626); // dark gray divider/borders
  static const Color buttonBorder = Color(0xFF333333);
  static const Color buttonFill = Color(0xFF1C1C1C);
  
  static const Color playhead = Color(0xFF5DCAA5); // teal/green accent
  
  // Track clip colors
  static const Color textClipFill = Color(0xFF3C3489);
  static const Color textClipBorder = Color(0xFF534AB7);
  
  static const Color stickerClipFill = Color(0xFF712B13);
  static const Color stickerClipBorder = Color(0xFF993C1D);
  
  static const Color videoClipFill1 = Color(0xFF085041);
  static const Color videoClipFill2 = Color(0xFF0F6E56);
  static const Color videoClipBorder = Color(0xFF0F6E56);
  
  static const Color audioClipFill = Color(0x8C712B13); // ~55% opacity of #712B13
  static const Color audioWaveform = Color(0xFFF0997B);
  
  // Text and UI states
  static const Color textPrimary = Color(0xFFF0F0F0); // near-white
  static const Color textSecondary = Color(0xFF9A9A9A); // mid-gray
  static const Color textMuted = Color(0xFF666666);
  static const Color iconPrimary = Color(0xFFD0D0D0);
  
  // Secondary button or active icon state
  static const Color activeAccent = Color(0xFF5DCAA5);

  // Styled button helper
  static ButtonStyle getButtonStyle({bool isPrimary = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: isPrimary ? activeAccent : buttonFill,
      foregroundColor: isPrimary ? Colors.black : textPrimary,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      side: BorderSide(color: isPrimary ? Colors.transparent : buttonBorder, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
