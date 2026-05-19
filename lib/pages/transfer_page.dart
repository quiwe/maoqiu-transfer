import 'package:flutter/material.dart';

import '../app.dart';
import '../utils/formatters.dart';
import '../widgets/transfer_progress_card.dart';

class TransferPage extends StatelessWidget {
  const TransferPage({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('传输进度')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final task = controller.taskById(taskId);
          if (task == null) {
            return const Center(child: Text('任务正在准备中'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              TransferProgressCard(task: task),
              const SizedBox(height: 18),
              Text(
                '文件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ...task.files.map(
                (file) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(formatBytes(file.fileSize)),
                    ),
                  ),
                ),
              ),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  task.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
