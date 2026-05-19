import 'dart:async';
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
  MobileScannerController? _scannerController;
  HotspotInvite? _invite;
  String? _error;
  bool _joining = false;
  bool _scanning = false;
  bool _startingScanner = false;
  bool _handledScan = false;
  bool _handledScannerError = false;
  bool get _supportsCameraScan => Platform.isAndroid;

  @override
  void dispose() {
    _payloadController.dispose();
    final scannerController = _scannerController;
    if (scannerController != null) {
      unawaited(scannerController.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scannerController = _scannerController;
    return Scaffold(
      appBar: AppBar(title: const Text('扫码接收')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_supportsCameraScan && _scanning && scannerController != null) ...[
            _ScannerPanel(
              controller: scannerController,
              onDetect: _handleScan,
              onDetectError: _handleScannerError,
              onClose: () {
                unawaited(_stopScanner());
              },
              onRetry: () {
                unawaited(_restartScanner());
              },
            ),
            const SizedBox(height: 14),
          ],
          if (_supportsCameraScan) ...[
            FilledButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_scannerButtonLabel),
              onPressed:
                  _scanning || _startingScanner ? null : _startScanner,
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
            onPressed: () => _parsePayload(),
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
              label: Text(_joining ? '正在准备' : _joinButtonLabel),
              onPressed: _joining ? null : () => _join(),
            ),
          ],
        ],
      ),
    );
  }

  String get _scannerButtonLabel {
    if (_startingScanner) {
      return '正在打开相机';
    }
    if (_scanning) {
      return '正在扫描';
    }
    return '打开相机扫码';
  }

  String get _joinButtonLabel {
    final invite = _invite;
    if (invite?.usesReceiverHotspot == true) {
      return '开启手机热点并接收';
    }
    return '连接热点并继续';
  }

  Future<void> _startScanner() async {
    if (_startingScanner || _scanning) {
      return;
    }

    setState(() {
      _error = null;
      _startingScanner = true;
    });

    final status = await Permission.camera.request();
    if (!mounted) {
      return;
    }

    if (!status.isGranted) {
      setState(() {
        _error = '需要相机权限才能扫码。';
        _startingScanner = false;
      });
      return;
    }

    final scannerController = _createScannerController();
    setState(() {
      _handledScan = false;
      _handledScannerError = false;
      _scannerController = scannerController;
      _scanning = true;
      _startingScanner = false;
    });
  }

  MobileScannerController _createScannerController() {
    return MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  Future<void> _stopScanner() async {
    final scannerController = _scannerController;
    try {
      await scannerController?.stop();
    } catch (_) {
      // Stopping is best-effort because the Android camera may still be
      // completing a previous start request.
    } finally {
      if (mounted) {
        setState(() {
          _scannerController = null;
          _scanning = false;
          _startingScanner = false;
        });
      }
      try {
        await scannerController?.dispose();
      } catch (_) {
        // Disposing after a native camera error is best-effort.
      }
    }
  }

  Future<void> _restartScanner() async {
    await _stopScanner();
    if (mounted) {
      await _startScanner();
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
    final invite = _parsePayload();
    await _stopScanner();
    if (invite != null && mounted) {
      await _join(invite);
    }
  }

  void _handleScannerError(Object error, StackTrace stackTrace) {
    if (_handledScannerError || !mounted) {
      return;
    }
    _handledScannerError = true;
    setState(() {
      _error = '相机识别异常，请点击重试，或把二维码内容粘贴到输入框后解析。';
    });
  }

  HotspotInvite? _parsePayload() {
    try {
      final invite = HotspotInvite.fromQrPayload(_payloadController.text);
      setState(() {
        _invite = invite;
        _error = invite.isExpired ? '邀请已过期' : null;
      });
      return invite.isExpired ? null : invite;
    } catch (error) {
      setState(() {
        _invite = null;
        _error = _payloadController.text.trim().isEmpty ? null : error.toString();
      });
      return null;
    }
  }

  Future<void> _join([HotspotInvite? scannedInvite]) async {
    final invite = scannedInvite ?? _invite;
    if (_joining || invite == null || invite.isExpired) {
      return;
    }

    setState(() => _joining = true);
    try {
      await AppControllerScope.of(context).joinHotspotInvite(invite);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_joinSuccessMessage(invite))),
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

  String _joinSuccessMessage(HotspotInvite invite) {
    if (invite.usesReceiverHotspot) {
      return '手机热点已开启，等待发送端连接并传输文件';
    }
    return '已通知发送端，请确认接收请求';
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.controller,
    required this.onDetect,
    required this.onDetectError,
    required this.onClose,
    required this.onRetry,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;
  final void Function(Object error, StackTrace stackTrace) onDetectError;
  final VoidCallback onClose;
  final VoidCallback onRetry;

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
              onDetectError: onDetectError,
              errorBuilder: (context, error) {
                return _ScannerErrorView(
                  onRetry: onRetry,
                  onClose: onClose,
                );
              },
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

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({
    required this.onRetry,
    required this.onClose,
  });

  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                '相机启动失败',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请重试，或粘贴二维码内容后解析。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                    onPressed: onRetry,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('关闭'),
                    onPressed: onClose,
                  ),
                ],
              ),
            ],
          ),
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
            if (invite.usesReceiverHotspot)
              const _Line(label: '方式', value: '本机开启手机热点')
            else ...[
              _Line(label: 'WiFi', value: invite.ssid),
              _Line(label: '密码', value: invite.password),
            ],
            _Line(label: '发送端', value: '${invite.hostIp}:${invite.port}'),
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
