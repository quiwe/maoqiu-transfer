import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app.dart';
import '../models/connection_invite.dart';
import '../models/transfer_file.dart';
import '../models/transfer_task.dart';
import '../services/app_controller.dart';
import '../utils/formatters.dart';
import '../widgets/transfer_progress_card.dart';

class QuickTransferPage extends StatefulWidget {
  const QuickTransferPage({super.key});

  @override
  State<QuickTransferPage> createState() => _QuickTransferPageState();
}

class _QuickTransferPageState extends State<QuickTransferPage> {
  final List<TransferFile> _files = [];
  bool _starting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('一键快传')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final session = controller.activeHotspotSession;
          final task = _activeTask(controller);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '待发送文件',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: const Text('选择文件'),
                    onPressed: session == null ? _pickFiles : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_files.isEmpty && session == null)
                const _EmptyFiles()
              else
                ..._visibleFiles(session).map(
                  (file) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FileTile(file: file),
                  ),
                ),
              const SizedBox(height: 16),
              if (session == null)
                FilledButton.icon(
                  icon: const Icon(Icons.bolt),
                  label: Text(_starting ? '正在创建' : '生成快传二维码'),
                  onPressed:
                      _files.isEmpty || _starting ? null : _startHotspotSession,
                )
              else
                _SessionPanel(
                  session: session,
                  message: controller.hotspotMessage,
                  task: task,
                  onStop: controller.stopHotspotSession,
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Iterable<TransferFile> _visibleFiles(HotspotSession? session) {
    return session?.files ?? _files;
  }

  TransferTask? _activeTask(AppController controller) {
    final taskId = controller.activeHotspotTaskId;
    if (taskId == null) {
      return null;
    }
    return controller.taskById(taskId);
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _files
        ..clear()
        ..addAll(
          result.files
              .where((file) => file.path != null && file.path!.isNotEmpty)
              .map(
                (file) => TransferFile(
                  fileName: file.name,
                  fileSize: file.size,
                  sha256: '',
                  localPath: file.path,
                ),
              ),
        );
    });
  }

  Future<void> _startHotspotSession() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await AppControllerScope.of(context).createHotspotSession(List.of(_files));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }
}

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.session,
    required this.message,
    required this.task,
    required this.onStop,
  });

  final HotspotSession session;
  final String? message;
  final TransferTask? task;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = session.invite.toQrPayload();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const _Line(label: '方式', value: '手机扫码后开启热点'),
            _Line(label: '本机', value: '${session.invite.hostIp}:${session.invite.port}'),
            _Line(label: '有效期', value: session.invite.expireAt.toLocal().toString()),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message!),
            ],
            if (task != null) ...[
              const SizedBox(height: 12),
              TransferProgressCard(task: task!),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('二维码内容'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(payload),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('关闭快传'),
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file});

  final TransferFile file;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatBytes(file.fileSize)),
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles();

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
        '请选择要发送的文件',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
