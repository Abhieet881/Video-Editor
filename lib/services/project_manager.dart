import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/video_editor_models.dart';

class ProjectManager {
  static final ProjectManager _instance = ProjectManager._internal();
  factory ProjectManager() => _instance;
  ProjectManager._internal();

  Future<String> _getDraftsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final draftsPath = '${directory.path}/drafts';
    final draftsDir = Directory(draftsPath);
    if (!await draftsDir.exists()) {
      await draftsDir.create(recursive: true);
    }
    return draftsPath;
  }

  Future<void> saveProject(Project project) async {
    project.updatedAt = DateTime.now();
    final draftsPath = await _getDraftsPath();
    final file = File('$draftsPath/${project.id}.json');
    final jsonString = jsonEncode(project.toJson());
    await file.writeAsString(jsonString);
  }

  Future<List<Project>> loadAllProjects() async {
    final draftsPath = await _getDraftsPath();
    final draftsDir = Directory(draftsPath);
    final files = draftsDir.listSync();
    final List<Project> projects = [];

    for (var fileEntity in files) {
      if (fileEntity is File && fileEntity.path.endsWith('.json')) {
        try {
          final jsonString = await fileEntity.readAsString();
          final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
          projects.add(Project.fromJson(jsonMap));
        } catch (e) {
          // Skip corrupt draft files
          print("Failed to load draft file: ${fileEntity.path}, error: $e");
        }
      }
    }
    // Sort projects by updated date descending
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<void> deleteProject(String id) async {
    final draftsPath = await _getDraftsPath();
    final file = File('$draftsPath/$id.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
