import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../services/protocol.dart';
import 'send_file_page.dart';

class ManualIpPage extends StatefulWidget {
  const ManualIpPage({super.key});

  @override
  State<ManualIpPage> createState() => _ManualIpPageState();
}

class _ManualIpPageState extends State<ManualIpPage> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _nameController = TextEditingController(text: 'Manual Device');
  final _portController =
      TextEditingController(text: TransferProtocol.tcpPort.toString());

  @override
  void dispose() {
    _ipController.dispose();
    _nameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手动输入 IP')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextFormField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                hintText: '192.168.1.20',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                final text = value?.trim() ?? '';
                final valid = RegExp(
                  r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}'
                  r'(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
                ).hasMatch(text);
                return valid ? null : '请输入有效 IPv4 地址';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final port = int.tryParse(value?.trim() ?? '');
                if (port == null || port <= 0 || port > 65535) {
                  return '请输入有效端口';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '设备名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('选择文件'),
              onPressed: _openSendPage,
            ),
          ],
        ),
      ),
    );
  }

  void _openSendPage() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final ip = _ipController.text.trim();
    final port = int.parse(_portController.text.trim());
    final name = _nameController.text.trim().isEmpty
        ? 'Manual Device'
        : _nameController.text.trim();
    final device = DeviceInfo(
      deviceId: 'manual-$ip-$port',
      deviceName: name,
      deviceType: 'desktop',
      ip: ip,
      port: port,
      version: TransferProtocol.appVersion,
      lastSeen: DateTime.now(),
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SendFilePage(device: device),
      ),
    );
  }
}
