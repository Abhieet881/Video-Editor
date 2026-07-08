import 'dart:convert';
import '../models/video_editor_models.dart';

class HistoryManager {
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  final int maxHistoryLength = 50;

  void pushState(Project project) {
    _redoStack.clear();
    final stateJson = jsonEncode(project.toJson());
    
    // Avoid pushing duplicate states consecutively
    if (_undoStack.isNotEmpty && _undoStack.last == stateJson) return;

    _undoStack.add(stateJson);
    if (_undoStack.length > maxHistoryLength) {
      _undoStack.removeAt(0);
    }
  }

  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;

  Project? undo(Project currentState) {
    if (!canUndo) return null;
    
    final currentJson = jsonEncode(currentState.toJson());
    _redoStack.add(currentJson);
    
    // Pop current state
    _undoStack.removeLast(); 
    final previousJson = _undoStack.last;
    
    return Project.fromJson(jsonDecode(previousJson));
  }

  Project? redo(Project currentState) {
    if (!canRedo) return null;
    
    final currentJson = jsonEncode(currentState.toJson());
    _undoStack.add(currentJson);
    
    final nextJson = _redoStack.removeLast();
    return Project.fromJson(jsonDecode(nextJson));
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
