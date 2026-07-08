import 'package:flutter/material.dart';
import '../services/editor_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EditorTheme.background,
      appBar: AppBar(
        backgroundColor: EditorTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: EditorTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Settings",
          style: TextStyle(color: EditorTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: EditorTheme.border, height: 1, thickness: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader("App Configuration"),
          _buildListTile(
            icon: Icons.high_quality_rounded,
            title: "Default Export Resolution",
            subtitle: "1080p (FHD)",
          ),
          _buildListTile(
            icon: Icons.aspect_ratio_rounded,
            title: "Default Aspect Ratio",
            subtitle: "9:16 (Vertical)",
          ),
          const Divider(color: EditorTheme.border, height: 32),
          _buildSectionHeader("Cache & Security"),
          _buildListTile(
            icon: Icons.cleaning_services_rounded,
            title: "Clear Temporary Cache",
            subtitle: "Deletes working timeline temp render files",
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Cache cleared successfully!")),
              );
            },
          ),
          _buildListTile(
            icon: Icons.security_rounded,
            title: "Protection Password Lock",
            subtitle: "Manage pin codes for protected drafts",
          ),
          const Divider(color: EditorTheme.border, height: 32),
          _buildSectionHeader("About"),
          _buildListTile(
            icon: Icons.info_outline_rounded,
            title: "AI Video Editor version",
            subtitle: "v1.2.0 (Premiere Pro Theme Edition)",
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: EditorTheme.playhead,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: EditorTheme.buttonFill,
        border: Border.all(color: EditorTheme.buttonBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: EditorTheme.iconPrimary),
        title: Text(title, style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: EditorTheme.textSecondary, fontSize: 10)),
        trailing: const Icon(Icons.chevron_right_rounded, color: EditorTheme.textSecondary, size: 18),
        onTap: onTap,
      ),
    );
  }
}
