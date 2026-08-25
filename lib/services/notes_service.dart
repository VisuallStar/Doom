import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Background notes service — stores notes as plain text files
/// so the agent doesn't need screen control for Samsung Notes.
class NotesService {
  Future<Directory> _notesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/agent_notes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitizeFilename(String title) {
    return title
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  /// Create a new note with title and content
  Future<String> createNote({required String title, required String content}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      final timestamp = DateTime.now().toIso8601String();
      final fullContent = '# $title\nCreated: $timestamp\n\n$content';
      await file.writeAsString(fullContent);
      return 'Note "$title" created successfully.';
    } catch (e) {
      return 'Error creating note: $e';
    }
  }

  /// Append text to an existing note
  Future<String> appendNote({required String title, required String content}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      if (!await file.exists()) {
        return await createNote(title: title, content: content);
      }
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('\n\n[$timestamp]\n$content', mode: FileMode.append);
      return 'Appended to note "$title" successfully.';
    } catch (e) {
      return 'Error appending to note: $e';
    }
  }

  /// List all saved notes
  Future<String> listNotes() async {
    try {
      final dir = await _notesDir();
      final files = await dir.list().where((f) => f is File && f.path.endsWith('.txt')).toList();
      if (files.isEmpty) {
        return 'No notes found.';
      }
      final sb = StringBuffer('Saved Notes:\n');
      for (final f in files) {
        final name = f.path.split('/').last.replaceAll('.txt', '');
        final stat = await (f as File).stat();
        final modified = stat.modified.toIso8601String().substring(0, 16);
        sb.writeln('  - $name (modified: $modified)');
      }
      return sb.toString().trim();
    } catch (e) {
      return 'Error listing notes: $e';
    }
  }

  /// Read a note by title
  Future<String> readNote({required String title}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      if (!await file.exists()) {
        // Try partial match
        final files = await dir.list().where((f) => f is File && f.path.endsWith('.txt')).toList();
        for (final f in files) {
          if (f.path.toLowerCase().contains(sanitized)) {
            return await (f as File).readAsString();
          }
        }
        return 'Note "$title" not found.';
      }
      return await file.readAsString();
    } catch (e) {
      return 'Error reading note: $e';
    }
  }

  /// Delete a note by title
  Future<String> deleteNote({required String title}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      if (!await file.exists()) {
        return 'Note "$title" not found.';
      }
      await file.delete();
      return 'Note "$title" deleted.';
    } catch (e) {
      return 'Error deleting note: $e';
    }
  }
}
