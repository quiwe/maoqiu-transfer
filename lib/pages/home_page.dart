import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/device_info.dart';
import '../services/app_controller.dart';
import '../services/tcp_server_service.dart';
import '../widgets/device_card.dart';
import '../widgets/receive_request_dialog.dart';
import '../widgets/transfer_progress_card.dart';
import 'join_transfer_page.dart';
import 'manual_ip_page.dart';
import 'quick_transfer_page.dart';
import 'send_file_page.dart';
import 'settings_page.dart';
import 'transfer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.startupFuture});

  final Future<void> startupFuture;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppController? _controller;
  StreamSubscription<IncomingTransferRequest>? _incomingSubscription;
  Future<void> _dialogQueue = Future.value();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppControllerScope.of(context);
    if (_controller == controller) {
      return;
    }

    _incomingSubscription?.cancel();
    _controller = controller;
    _incomingSubscription = controller.incomingRequests.listen((request) {
      _dialogQueue = _dialogQueue.then((_) => _showReceiveDialog(request));
    });
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return FutureBuilder<void>(
      future: widget.startupFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('毛球互传'),
            actions: [
              IconButton(
                tooltip: '刷新本机 IP',
                icon: const Icon(Icons.refresh),
                onPressed: controller.refreshLocalDevice,
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !controller.isStarted) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.startupError != null) {
                return _StartupError(message: controller.startupError!);
              }

              return _HomeContent(controller: controller);
            },
          ),
        );
      },
    );
  }

  Future<void> _showReceiveDialog(IncomingTransferRequest request) async {
    if (!mounted) {
      request.reject();
      return;
    }

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ReceiveRequestDialog(request: request),
        ) ??
        false;

    if (accepted) {
      request.accept();
    } else {
      request.reject();
    }
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _LocalDevicePanel(device: controller.localDevice),
        const SizedBox(height: 14),
        const _QuickActions(),
        const SizedBox(height: 20),
        _SectionTitle(
          title: '附近设备',
          trailing: Text('${controller.nearbyDevices.length} 台在线'),
        ),
        const SizedBox(height: 10),
        if (controller.nearbyDevices.isEmpty)
          const _EmptyBlock(text: '同一 WiFi 下打开客户端后会出现在这里')
        else
          ...controller.nearbyDevices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DeviceCard(
                device: device,
                onTap: () => _openSendPage(context, device),
              ),
            ),
          ),
        const SizedBox(height: 20),
        const _SectionTitle(title: '传输任务'),
        const SizedBox(height: 10),
        if (controller.transfers.isEmpty)
          const _EmptyBlock(text: '暂无传输任务')
        else
          ...controller.transfers.take(5).map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransferProgressCard(
                    task: task,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TransferPage(taskId: task.taskId),
                        ),
                      );
                    },
                  ),
                ),
              ),
      ],
    );
  }

  void _openSendPage(BuildContext context, DeviceInfo device) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendFilePage(device: device),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.bolt),
          label: const Text('一键快传'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QuickTransferPage(),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('扫码接收'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const JoinTransferPage(),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_location_alt_outlined),
          label: const Text('手动 IP'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ManualIpPage(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LocalDevicePanel extends StatelessWidget {
  const _LocalDevicePanel({required this.device});

  final DeviceInfo? device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              device?.isMobile == true ? Icons.phone_android : Icons.computer,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device?.deviceName ?? '正在读取本机设备',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    device == null ? '--' : '${device!.ip}:${device!.port}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('启动失败', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
