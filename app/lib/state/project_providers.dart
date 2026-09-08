import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Display name of the project currently loaded/being edited.
final currentProjectNameProvider = StateProvider<String>((ref) => 'Untitled Project');
