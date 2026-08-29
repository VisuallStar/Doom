import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Background notes service — stores notes as plain text files
/// so the agent doesn't need screen control for quick notes.
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

  Future<File?> _findNoteFile(String title) async {
    final dir = await _notesDir();
    final sanitized = _sanitizeFilename(title);
    final file = File('${dir.path}/${sanitized}.txt');
    if (await file.exists()) return file;

    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.txt'))
        .toList();
    for (final f in files) {
      if (f.path.toLowerCase().contains(sanitized)) {
        return f as File;
      }
    }
    return null;
  }

  String _bodyFromNoteContent(String content, String title) {
    final lines = content.split('\n');
    final bodyLines = <String>[];
    var skippedHeader = false;

    for (final line in lines) {
      if (!skippedHeader) {
        if (line.startsWith('# ') || line.startsWith('Created:')) continue;
        if (line.trim().isEmpty && bodyLines.isEmpty) continue;
        skippedHeader = true;
      }
      bodyLines.add(line);
    }

    final body = bodyLines.join('\n').trim();
    return body.isEmpty ? content.trim() : body;
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
      final file = await _findNoteFile(title);
      if (file == null) {
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
      final file = await _findNoteFile(title);
      if (file == null) {
        return 'Note "$title" not found.';
      }
      await file.delete();
      return 'Note "$title" deleted.';
    } catch (e) {
      return 'Error deleting note: $e';
    }
  }

  /// Create a checklist-style note
  Future<String> createList({required String title, required List<String> items}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      final timestamp = DateTime.now().toIso8601String().substring(0, 19);
      final sb = StringBuffer('# $title\nCreated: $timestamp\n\n');
      for (final item in items) {
        sb.writeln('- [ ] $item');
      }
      await file.writeAsString(sb.toString());
      return 'List "$title" created successfully with ${items.length} items.';
    } catch (e) {
      return 'Error creating list: $e';
    }
  }

  /// Append items to an existing list note
  Future<String> addToList({required String title, required List<String> items}) async {
    try {
      final dir = await _notesDir();
      final sanitized = _sanitizeFilename(title);
      final file = File('${dir.path}/${sanitized}.txt');
      if (!await file.exists()) {
        return await createList(title: title, items: items);
      }
      final sb = StringBuffer();
      for (final item in items) {
        sb.writeln('- [ ] $item');
      }
      await file.writeAsString('\n${sb.toString().trimRight()}', mode: FileMode.append);
      return 'Added ${items.length} items to "$title".';
    } catch (e) {
      return 'Error adding to list: $e';
    }
  }

  /// Mark a list item as done
  Future<String> checkListItem({required String title, required String item}) async {
    try {
      final file = await _findNoteFile(title);
      if (file == null) {
        return 'List "$title" not found.';
      }
      String content = await file.readAsString();

      final regex = RegExp(r'-\s*\[\s*\]\s*' + RegExp.escape(item), caseSensitive: false);
      if (regex.hasMatch(content)) {
        content = content.replaceFirstMapped(regex, (match) {
          final matchedText = match.group(0)!;
          return matchedText.replaceFirst(RegExp(r'\[\s*\]'), '[x]');
        });
        await file.writeAsString(content);
        return 'Marked "$item" as done in "$title".';
      } else {
        return 'Item "$item" not found in "$title" or already checked.';
      }
    } catch (e) {
      return 'Error checking list item: $e';
    }
  }

  /// Export a note as a real PDF file via the share dialog.
  Future<String> exportNoteToPdf({required String title}) async {
    try {
      final file = await _findNoteFile(title);
      if (file == null) {
        return 'Note "$title" not found.';
      }

      final rawContent = await file.readAsString();
      final body = _bodyFromNoteContent(rawContent, title);
      final sanitized = _sanitizeFilename(title);

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              body,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.4),
            ),
          ],
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final exportFile = File('${tempDir.path}/$sanitized.pdf');
      await exportFile.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(exportFile.path, mimeType: 'application/pdf')],
        text: 'Exported Note: $title',
      );
      return 'Exported "$title" as PDF.';
    } catch (e) {
      return 'Error exporting note to PDF: $e';
    }
  }
}
