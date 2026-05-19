import 'package:flutter/material.dart';

import '../app.dart';
import '../models/connection_invite.dart';

class JoinTransferPage extends StatefulWidget {
  const JoinTransferPage({super.key});

  @override
  State<JoinTransferPage> createState() => _JoinTransferPageState();
}

class _JoinTransferPageState extends State<JoinTransferPage> {
  final _payloadController = TextEditingController();
  HotspotInvite? _invite;
  String? _error;
  bool _joining = false;

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码接收')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
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
              label: Text(_joining ? '正在通知发送端' : '我已加入，继续'),
              onPressed: _joining ? null : _join,
            ),
          ],
        ],
      ),
    );
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
