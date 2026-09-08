import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/fixture_profile.dart';
import '../../models/project_data.dart';

class ProjectFileInfo {
  final String name;
  final File file;
  final DateTime modified;
  final int sizeBytes;

  const ProjectFileInfo({
    required this.name,
    required this.file,
    required this.modified,
    required this.sizeBytes,
  });
}

/// Reads/writes show files as pretty-printed JSON under the app's documents
/// directory, so they show up in the Files tab and survive app restarts.
class ProjectStorage {
  Future<Directory> _projectsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/dmx_projects');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<ProjectFileInfo>> list() async {
    final dir = await _projectsDir();
    final entries = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    final infos = <ProjectFileInfo>[];
    for (final file in entries) {
      final stat = await file.stat();
      final fileName = file.uri.pathSegments.last;
      final name = fileName.substring(0, fileName.length - '.json'.length);
      infos.add(ProjectFileInfo(name: name, file: file, modified: stat.modified, sizeBytes: stat.size));
    }
    infos.sort((a, b) => b.modified.compareTo(a.modified));
    return infos;
  }

  Future<File> save(String name, ProjectData data) async {
    final dir = await _projectsDir();
    final safeName = name.trim().isEmpty ? 'Untitled' : name.trim();
    final file = File('${dir.path}/$safeName.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data.toJson()));
    return file;
  }

  Future<ProjectData> loadFile(File file, {required List<FixtureProfile> builtIns}) async {
    final content = await file.readAsString();
    return ProjectData.fromJson(jsonDecode(content) as Map<String, dynamic>, builtIns: builtIns);
  }

  Future<void> delete(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
