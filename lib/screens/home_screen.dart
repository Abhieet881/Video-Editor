import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/video_editor_models.dart';
import '../services/project_manager.dart';
import 'media_picker_screen.dart';
import 'editor_screen.dart';

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
            content: Text('This draft is protected. Disable Protection Mode in Editor settings first.'),
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
    // Generate a template project
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

    // Save project draft to database
    _projectManager.saveProject(project);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditorScreen(project: project),
      ),
    ).then((_) => _loadDrafts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "AI Video Editor",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            foreground: Paint()
              ..shader = LinearGradient(
                colors: [Colors.tealAccent.shade400, Colors.cyanAccent.shade400],
              ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              // Settings implementation in Phase 8
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings Screen (Phase 8)')),
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
              const SizedBox(height: 10),
              // Big CTA Button for new project
              Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      Colors.tealAccent.shade700.withOpacity(0.8),
                      Colors.cyan.shade900.withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.tealAccent.shade400.withOpacity(0.15),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    )
                  ],
                  border: Border.all(
                    color: Colors.tealAccent.shade400.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _createNewProject,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.tealAccent, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 32,
                              color: Colors.tealAccent,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "New Project",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Create and edit a multi-track masterpiece",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Tab Selector
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.tealAccent.shade400,
                indicatorWeight: 3,
                labelColor: Colors.tealAccent.shade400,
                unselectedLabelColor: Colors.grey.shade500,
                labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: "Drafts"),
                  Tab(text: "Templates"),
                ],
              ),
              const SizedBox(height: 16),
              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Drafts Grid
                    _buildDraftsTab(),
                    // Templates Grid
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
      return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
    }

    if (_drafts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              "No drafts yet",
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Your edit projects will be saved here automatically",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: _drafts.length,
      itemBuilder: (context, index) {
        final project = _drafts[index];
        final formattedDate = DateFormat('MMM dd, yyyy').format(project.updatedAt);
        
        // Calculate total timeline duration
        int maxDuration = 0;
        for (var track in project.tracks) {
          for (var clip in track.clips) {
            final end = clip.startInTimelineMs + clip.durationMs;
            if (end > maxDuration) maxDuration = end;
          }
        }
        final durationSec = (maxDuration / 1000).toStringAsFixed(1);

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade900, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => EditorScreen(project: project),
                ),
              ).then((_) => _loadDrafts());
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail block
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.video_collection_outlined,
                            size: 40,
                            color: Colors.tealAccent.shade400.withOpacity(0.5),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "${durationSec}s",
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Metadata block
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18, color: Colors.white60),
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deleteDraft(project.id);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete Draft', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formattedDate,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.shade400.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              project.aspectRatio.name,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.tealAccent.shade400,
                                fontWeight: FontWeight.bold,
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
        );
      },
    );
  }

  Widget _buildTemplatesTab() {
    final templates = [
      {'name': 'TikTok Trend', 'desc': 'Fast pacing, sync beats, 9:16', 'ratio': EditorAspectRatio.ratio9to16},
      {'name': 'YouTube Intro', 'desc': 'Cinematic horizontal, 16:9', 'ratio': EditorAspectRatio.ratio16to9},
      {'name': 'Instagram Post', 'desc': 'Minimalist lifestyle square, 1:1', 'ratio': EditorAspectRatio.ratio1to1},
      {'name': 'Vlog Highlights', 'desc': 'Smooth transitions, 9:16', 'ratio': EditorAspectRatio.ratio9to16},
    ];

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final t = templates[index];
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161618),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade900, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _loadTemplate(t['name'] as String, t['ratio'] as EditorAspectRatio),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade900.withOpacity(0.4), Colors.cyan.shade900.withOpacity(0.4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.auto_awesome_outlined,
                        size: 44,
                        color: Colors.tealAccent.shade400,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['name'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t['desc'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (t['ratio'] as EditorAspectRatio).name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent.shade400,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: Colors.white60,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
