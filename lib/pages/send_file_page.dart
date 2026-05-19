import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../models/device_info.dart';
import '../models/transfer_file.dart';
import '../utils/formatters.dart';
import 'transfer_page.dart';

class SendFilePage extends StatefulWidget {
  const SendFilePage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<SendFilePage> createState() => _SendFilePageState();
}

class _SendFilePageState extends State<SendFilePage> {
  final List<TransferFile> _files = [];
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final totalBytes = _files.fold<int>(0, (sum, file) => sum + file.fileSize);
    return Scaffold(
      appBar: AppBar(title: Text('发送到 ${widget.device.deviceName}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _TargetPanel(device: widget.device),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '已选择文件',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.attach_file),
                label: const Text('选择文件'),
                onPressed: _pickFiles,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_files.isEmpty)
            const _NoFiles()
          else
            ..._files.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SelectedFileTile(
                  file: file,
                  onRemove: () => setState(() => _files.remove(file)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('总大小：${formatBytes(totalBytes)}'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: Text(_starting ? '正在创建任务' : '开始发送'),
            onPressed: _files.isEmpty || _starting ? null : _startSending,
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || !mounted) {
      return;
    }

    final picked = result.files
        .where((file) => file.path != null && file.path!.isNotEmpty)
        .map(
          (file) => TransferFile(
            fileName: file.name,
            fileSize: file.size,
            sha256: '',
            localPath: file.path,
          ),
        );

    setState(() {
      _files
        ..clear()
        ..addAll(picked);
    });
  }

  void _startSending() {
    setState(() => _starting = true);
    final controller = AppControllerScope.of(context);
    final taskId = controller.sendFiles(widget.device, List.of(_files));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TransferPage(taskId: taskId),
      ),
    );
  }
}

class _TargetPanel extends StatelessWidget {
  const _TargetPanel({required this.device});

  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(device.isMobile ? Icons.phone_android : Icons.computer),
        title: Text(device.deviceName),
        subtitle: Text('${device.ip}:${device.port}'),
      ),
    );
  }
}

class _NoFiles extends StatelessWidget {
  const _NoFiles();

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
        '请选择一个或多个文件',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SelectedFileTile extends StatelessWidget {
  const _SelectedFileTile({required this.file, required this.onRemove});

  final TransferFile file;
  final VoidCallback onRemove;

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
        trailing: IconButton(
          tooltip: '移除',
          icon: const Icon(Icons.close),
          onPressed: onRemove,
        ),
      ),
    );
  }
}
