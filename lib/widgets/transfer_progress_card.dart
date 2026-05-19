import 'package:flutter/material.dart';

import '../models/transfer_task.dart';
import '../utils/formatters.dart';

class TransferProgressCard extends StatelessWidget {
  const TransferProgressCard({
    super.key,
    required this.task,
    this.onTap,
  });

  final TransferTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final directionIcon = task.direction == TransferDirection.send
        ? Icons.north_east
        : Icons.south_west;

    return Card(
      color: theme.colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(directionIcon, color: _statusColor(theme)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.currentFileName ?? '传输任务',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_statusLabel(task.status)),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _progressValue),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  Text('${(task.progress * 100).toStringAsFixed(0)}%'),
                  Text('${formatBytes(task.transferredBytes)} / ${formatBytes(task.totalBytes)}'),
                  Text(formatSpeed(task.speedBytesPerSecond)),
                  Text(task.peerDeviceName),
                ],
              ),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.errorMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double? get _progressValue {
    if (task.status == TransferStatus.pending ||
        task.status == TransferStatus.waitingAccept) {
      return null;
    }
    return task.progress;
  }

  Color _statusColor(ThemeData theme) {
    switch (task.status) {
      case TransferStatus.completed:
        return theme.colorScheme.tertiary;
      case TransferStatus.failed:
      case TransferStatus.rejected:
      case TransferStatus.cancelled:
        return theme.colorScheme.error;
      case TransferStatus.pending:
      case TransferStatus.waitingAccept:
      case TransferStatus.transferring:
        return theme.colorScheme.primary;
    }
  }

  String _statusLabel(TransferStatus status) {
    switch (status) {
      case TransferStatus.pending:
        return '准备中';
      case TransferStatus.waitingAccept:
        return '等待确认';
      case TransferStatus.transferring:
        return '传输中';
      case TransferStatus.completed:
        return '完成';
      case TransferStatus.failed:
        return '失败';
      case TransferStatus.rejected:
        return '已拒绝';
      case TransferStatus.cancelled:
        return '已取消';
    }
  }
}
