import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import 'chase_editor_screen.dart';

class ChasesScreen extends ConsumerWidget {
  const ChasesScreen({super.key});

  Future<void> _open(BuildContext context, Chase chase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChaseEditorScreen(existing: chase)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chases = ref.watch(chasesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chases')),
      body: chases.isEmpty
          ? const Center(
              child: Text('No chases yet — tap + to create one', style: TextStyle(color: AppColors.textFaint)),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: chases.length,
              itemBuilder: (context, index) {
                final chase = chases[index];
                final onDashboard = ref
                    .watch(dashboardTriggersProvider)
                    .any((t) => t.id == chase.id && t.kind == TriggerKind.chase);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.fast_forward_outlined, color: AppColors.accent),
                    title: Text(chase.name),
                    subtitle: Text(
                      '${chase.steps.length} steps · ${chase.stepSeconds.toStringAsFixed(2)}s/step',
                      style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                    onTap: () => _open(context, chase),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            onDashboard ? Icons.dashboard : Icons.dashboard_customize_outlined,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            hoverColor: AppColors.accent.withValues(alpha: 0.15),
                            highlightColor: AppColors.accent.withValues(alpha: 0.25),
                          ),
                          tooltip: onDashboard ? 'Remove from Dashboard' : 'Add to Dashboard',
                          onPressed: () {
                            final notifier = ref.read(dashboardTriggersProvider.notifier);
                            notifier.toggle(chase.id, TriggerKind.chase);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  onDashboard
                                      ? 'Removed "${chase.name}" from Dashboard'
                                      : 'Added "${chase.name}" to Dashboard',
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () => ref.read(chasesProvider.notifier).duplicate(chase.id),
                          tooltip: 'Duplicate',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => ref.read(chasesProvider.notifier).remove(chase.id),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final chase = ref.read(chasesProvider.notifier).create('New Chase');
          _open(context, chase);
        },
        tooltip: 'New Chase',
        child: const Icon(Icons.add),
      ),
    );
  }
}
