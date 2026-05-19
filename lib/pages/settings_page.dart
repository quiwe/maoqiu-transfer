import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/transfer_task.dart';
import '../utils/formatters.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final records = controller.history.records;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('保存目录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: SelectableText(
                    controller.settings.saveDirectory ?? '--',
                    maxLines: 2,
                  ),
                  trailing: FilledButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('修改'),
                    onPressed: () => _chooseDirectory(context),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '历史记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清空'),
                    onPressed: records.isEmpty
                        ? null
                        : () => controller.clearHistory(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                const _EmptyHistory()
              else
                ...records.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryTile(record: record),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _chooseDirectory(BuildContext context) async {
    final controller = AppControllerScope.of(context);
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) {
      return;
    }
    await controller.setSaveDirectory(path);
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final TransferHistoryRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = record.direction == TransferDirection.send ? '发送' : '接收';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          record.direction == TransferDirection.send
              ? Icons.north_east
              : Icons.south_west,
        ),
        title: Text(record.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$direction · ${record.peerDeviceName} · ${formatBytes(record.fileSize)} · ${formatDateTime(record.createdAt)}',
          maxLines: 2,
        ),
        trailing: Text(_statusLabel(record.status)),
      ),
    );
  }

  String _statusLabel(TransferStatus status) {
    switch (status) {
      case TransferStatus.completed:
        return '完成';
      case TransferStatus.failed:
        return '失败';
      case TransferStatus.rejected:
        return '已拒绝';
      case TransferStatus.cancelled:
        return '已取消';
      case TransferStatus.pending:
        return '等待';
      case TransferStatus.waitingAccept:
        return '待确认';
      case TransferStatus.transferring:
        return '传输中';
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '暂无历史记录',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
