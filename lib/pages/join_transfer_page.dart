import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app.dart';
import '../models/connection_invite.dart';

class JoinTransferPage extends StatefulWidget {
  const JoinTransferPage({super.key});

  @override
  State<JoinTransferPage> createState() => _JoinTransferPageState();
}

class _JoinTransferPageState extends State<JoinTransferPage> {
  final _payloadController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  HotspotInvite? _invite;
  String? _error;
  bool _joining = false;
  bool _scanning = false;
  bool _handledScan = false;
  bool get _supportsCameraScan => Platform.isAndroid;

  @override
  void dispose() {
    _payloadController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码接收')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_supportsCameraScan && _scanning) ...[
            _ScannerPanel(
              controller: _scannerController,
              onDetect: _handleScan,
              onClose: () {
                _stopScanner();
              },
            ),
            const SizedBox(height: 14),
          ],
          if (_supportsCameraScan) ...[
            FilledButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_scanning ? '正在扫描' : '打开相机扫码'),
              onPressed: _scanning ? null : _startScanner,
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _payloadController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '二维码内容',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _parsePayload(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('解析邀请'),
            onPressed: _parsePayload,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_invite != null) ...[
            const SizedBox(height: 18),
            _InvitePanel(invite: _invite!),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.wifi),
              label: Text(_joining ? '正在连接并通知发送端' : '连接热点并继续'),
              onPressed: _joining ? null : _join,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = '需要相机权限才能扫码。');
      return;
    }

    setState(() {
      _error = null;
      _handledScan = false;
      _scanning = true;
    });
    await _scannerController.start();
  }

  Future<void> _stopScanner() async {
    await _scannerController.stop();
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_handledScan) {
      return;
    }

    String? rawValue;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        rawValue = value;
        break;
      }
    }
    if (rawValue == null || rawValue.trim().isEmpty) {
      return;
    }

    _handledScan = true;
    _payloadController.text = rawValue;
    _parsePayload();
    await _stopScanner();
  }

  void _parsePayload() {
    try {
      final invite = HotspotInvite.fromQrPayload(_payloadController.text);
      setState(() {
        _invite = invite;
        _error = invite.isExpired ? '邀请已过期' : null;
      });
    } catch (error) {
      setState(() {
        _invite = null;
        _error = _payloadController.text.trim().isEmpty ? null : error.toString();
      });
    }
  }

  Future<void> _join() async {
    final invite = _invite;
    if (invite == null || invite.isExpired) {
      return;
    }

    setState(() => _joining = true);
    try {
      await AppControllerScope.of(context).joinHotspotInvite(invite);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已通知发送端，请确认接收请求')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _joining = false;
        _error = error.toString();
      });
    }
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.controller,
    required this.onDetect,
    required this.onClose,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: onDetect,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: '关闭扫码',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitePanel extends StatelessWidget {
  const _InvitePanel({required this.invite});

  final HotspotInvite invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            _Line(label: 'WiFi', value: invite.ssid),
            _Line(label: '密码', value: invite.password),
            _Line(label: '主机', value: '${invite.hostIp}:${invite.port}'),
            _Line(label: '有效期', value: invite.expireAt.toLocal().toString()),
          ],
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
