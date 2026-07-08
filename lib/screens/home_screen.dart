import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/video_editor_models.dart';
import '../services/project_manager.dart';
import '../services/editor_theme.dart';
import 'media_picker_screen.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProjectManager _projectManager = ProjectManager();
  List<Project> _drafts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDrafts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    setState(() => _isLoading = true);
    try {
      final drafts = await _projectManager.loadAllProjects();
      setState(() {
        _drafts = drafts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load drafts: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _deleteDraft(String id) async {
    try {
      final project = _drafts.firstWhere((p) => p.id == id);
      if (project.isProtected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This draft is protected. Disable Protection Mode in Settings first.'),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      await _projectManager.deleteProject(id);
      _loadDrafts();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft deleted successfully'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete draft: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _createNewProject() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MediaPickerScreen(),
      ),
    ).then((_) => _loadDrafts());
  }

  void _loadTemplate(String templateName, EditorAspectRatio ratio) {
    final project = Project(
      id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: '$templateName Template',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      aspectRatio: ratio,
      tracks: [
        Track(id: 'track_main_video', type: TrackType.mainVideo, zOrder: 0, clips: []),
        Track(id: 'track_text_1', type: TrackType.text, zOrder: 1, clips: [
          TimelineClip(
            id: 'text_template_welcome',
            startInTimelineMs: 500,
            durationMs: 3000,
            startInSourceMs: 0,
            transform: ClipTransform(scale: 1.3, y: -20.0),
            effects: [],
            textContent: "Welcome to $templateName!",
          )
        ]),
        Track(id: 'track_audio_1', type: TrackType.audio, zOrder: -1, clips: []),
      ],
    );

    _projectManager.saveProject(project);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditorScreen(project: project),
      ),
    ).then((_) => _loadDrafts());
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSec = seconds % 60;
    return '$minutes:${remainingSec.toString().padLeft(2, '0')}';
  }

  int _calculateProjectDuration(Project project) {
    int maxDuration = 0;
    for (var track in project.tracks) {
      for (var clip in track.clips) {
        final end = clip.startInTimelineMs + clip.durationMs;
        if (end > maxDuration) maxDuration = end;
      }
    }
    return maxDuration;
  }

  // ==========================================
  // DRAFT LONG-PRESS CONTEXT MENU ACTIONS
  // ==========================================

  void _showDraftContextMenu(Project project) {
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
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                child: Text(
                  project.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: EditorTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: EditorTheme.border, height: 1),
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Rename Project", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _renameProjectDialog(project);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Duplicate Project", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _duplicateProject(project);
                },
              ),
              ListTile(
                leading: const Icon(Icons.security_rounded, color: EditorTheme.iconPrimary),
                title: const Text("Set Protection Lock", style: TextStyle(color: EditorTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _setProtectionDialog(project);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                title: const Text("Delete Project", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteDraft(project.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _renameProjectDialog(Project project) {
    final controller = TextEditingController(text: project.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: EditorTheme.buttonFill,
          title: const Text("Rename Project", style: TextStyle(color: EditorTheme.textPrimary)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: EditorTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: "Enter new name...",
              hintStyle: TextStyle(color: EditorTheme.textSecondary),
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
                if (controller.text.trim().isNotEmpty) {
                  setState(() {
                    project.name = controller.text.trim();
                  });
                  _projectManager.saveProject(project);
                  _loadDrafts();
                }
                Navigator.pop(context);
              },
              style: EditorTheme.getButtonStyle(isPrimary: true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _duplicateProject(Project project) {
    final duplicate = project.copy();
    final newId = 'proj_${DateTime.now().millisecondsSinceEpoch}_dup';
    // Deep clone parameters with new ID
    final duplicatedProject = Project(
      id: newId,
      name: "${project.name} Copy",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      aspectRatio: project.aspectRatio,
      thumbnailPath: project.thumbnailPath,
      tracks: duplicate.tracks,
      isProtected: project.isProtected,
      protectionPassword: project.protectionPassword,
      protectionExpiry: project.protectionExpiry,
    );

    _projectManager.saveProject(duplicatedProject);
    _loadDrafts();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project duplicated successfully')),
    );
  }

  void _setProtectionDialog(Project project) {
    final passwordController = TextEditingController(text: project.protectionPassword);
    bool isProtectedLocal = project.isProtected;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: EditorTheme.buttonFill,
              title: const Text("Draft Protection Settings", style: TextStyle(color: EditorTheme.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("Enable Protection", style: TextStyle(color: EditorTheme.textPrimary, fontSize: 14)),
                    subtitle: const Text("Requires code/protection status validation", style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11)),
                    value: isProtectedLocal,
                    activeColor: EditorTheme.playhead,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setModalState(() {
                        isProtectedLocal = val;
                      });
                    },
                  ),
                  if (isProtectedLocal) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      style: const TextStyle(color: EditorTheme.textPrimary),
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password / PIN",
                        labelStyle: TextStyle(color: EditorTheme.textSecondary),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: EditorTheme.border)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: EditorTheme.playhead)),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: EditorTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      project.isProtected = isProtectedLocal;
                      project.protectionPassword = isProtectedLocal ? passwordController.text : null;
                      if (isProtectedLocal) {
                        project.protectionExpiry = DateTime.now().add(const Duration(days: 7)); // default 1 week
                      } else {
                        project.protectionExpiry = null;
                      }
                    });
                    _projectManager.saveProject(project);
                    _loadDrafts();
                    Navigator.pop(context);
                  },
                  style: EditorTheme.getButtonStyle(isPrimary: true),
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // SCREEN BUILD METHODS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EditorTheme.background, // Premiere true black
      appBar: AppBar(
        backgroundColor: EditorTheme.background,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Projects",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: EditorTheme.textPrimary,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: EditorTheme.border, height: 1, thickness: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: EditorTheme.iconPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Full-width New Project Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _createNewProject,
                  icon: const Icon(Icons.add_rounded, color: EditorTheme.playhead, size: 20),
                  label: const Text(
                    "New Project",
                    style: TextStyle(color: EditorTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: EditorTheme.buttonFill,
                    side: const BorderSide(color: EditorTheme.buttonBorder, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Tab Bar row
              TabBar(
                controller: _tabController,
                indicatorColor: EditorTheme.playhead, // teal selected underline indicator
                indicatorWeight: 2,
                labelColor: EditorTheme.playhead,
                unselectedLabelColor: EditorTheme.textSecondary,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: "Drafts"),
                  Tab(text: "Templates"),
                ],
              ),
              const SizedBox(height: 16),
              // Grid TabViews
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDraftsTab(),
                    _buildTemplatesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraftsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: EditorTheme.playhead));
    }

    if (_drafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined, size: 48, color: EditorTheme.textMuted),
            const SizedBox(height: 12),
            const Text(
              "Start your first project",
              style: TextStyle(fontSize: 16, color: EditorTheme.textPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createNewProject,
              style: EditorTheme.getButtonStyle(isPrimary: true),
              child: const Text("New Project"),
            ),
          ],
        ),
      );
    }

    // Determine if we need an empty dash add tile to prevent sparse row layout (if drafts list is less than 3)
    final bool showAddTile = _drafts.length < 3;
    final int gridItemCount = _drafts.length + (showAddTile ? 1 : 0);

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 3-column grid
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.65, // 3:4 aspect ratio friendly child ratio
      ),
      itemCount: gridItemCount,
      itemBuilder: (context, index) {
        if (index == _drafts.length) {
          // Render dashed-border empty "add" tile
          return GestureDetector(
            onTap: _createNewProject,
            child: Container(
              decoration: BoxDecoration(
                color: EditorTheme.background,
                border: Border.all(color: EditorTheme.buttonBorder, width: 1.0, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(Icons.add_rounded, color: EditorTheme.textSecondary, size: 28),
              ),
            ),
          );
        }

        final project = _drafts[index];
        final formattedDate = DateFormat('MMM dd, yyyy').format(project.updatedAt);
        final durationMs = _calculateProjectDuration(project);
        final durationStr = _formatDuration(durationMs);

        final bool hasThumbnail = project.thumbnailPath != null && File(project.thumbnailPath!).existsSync();

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => EditorScreen(project: project),
              ),
            ).then((_) => _loadDrafts());
          },
          onLongPress: () => _showDraftContextMenu(project),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 3:4 Aspect ratio thumbnail with rounded corners
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video thumbnail or dark placeholder gradient
                      hasThumbnail
                          ? Image.file(File(project.thumbnailPath!), fit: BoxFit.cover)
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF141416), Color(0xFF262628)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.movie_filter_outlined, color: EditorTheme.textSecondary, size: 24),
                              ),
                            ),
                      // Lock icon if protected
                      if (project.isProtected)
                        const Positioned(
                          top: 6,
                          left: 6,
                          child: Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: EditorTheme.playhead,
                          ),
                        ),
                      // Duration badge
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            durationStr,
                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Title text
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: EditorTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              // Last-edited date
              Text(
                formattedDate,
                style: const TextStyle(fontSize: 9, color: EditorTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTemplatesTab() {
    final templates = [
      {'name': 'TikTok Trend', 'desc': 'Fast pacing vertical timeline', 'ratio': EditorAspectRatio.ratio9to16},
      {'name': 'YouTube Intro', 'desc': 'Cinematic horizontal cinematic', 'ratio': EditorAspectRatio.ratio16to9},
      {'name': 'Instagram Post', 'desc': 'Minimalist lifestyle square', 'ratio': EditorAspectRatio.ratio1to1},
    ];

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.65,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final name = template['name'] as String;
        final ratio = template['ratio'] as EditorAspectRatio;

        return GestureDetector(
          onTap: () => _loadTemplate(name, ratio),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F362F), Color(0xFF08221D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        ratio == EditorAspectRatio.ratio16to9 
                            ? Icons.tablet_android_rounded 
                            : Icons.phone_android_rounded,
                        color: EditorTheme.playhead.withOpacity(0.8),
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: EditorTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ratio.name.split('.').last.replaceAll('ratio', '').replaceAll('to', ':'),
                style: const TextStyle(fontSize: 9, color: EditorTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
