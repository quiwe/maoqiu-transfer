import 'package:flutter/material.dart';

import '../services/tcp_server_service.dart';
import '../utils/formatters.dart';

class ReceiveRequestDialog extends StatelessWidget {
  const ReceiveRequestDialog({super.key, required this.request});

  final IncomingTransferRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('收到文件传输请求'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('来自：${request.senderDeviceName}'),
            const SizedBox(height: 8),
            Text('数量：${request.files.length} 个文件'),
            const SizedBox(height: 8),
            Text('大小：${formatBytes(request.totalBytes)}'),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: request.files.length,
                  itemBuilder: (context, index) {
                    final file = request.files[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(formatBytes(file.fileSize)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('拒绝'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('接收'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
