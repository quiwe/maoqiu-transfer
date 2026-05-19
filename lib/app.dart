import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/app_controller.dart';

class MaoQiuTransferApp extends StatefulWidget {
  const MaoQiuTransferApp({super.key});

  @override
  State<MaoQiuTransferApp> createState() => _MaoQiuTransferAppState();
}

class _MaoQiuTransferAppState extends State<MaoQiuTransferApp> {
  late final AppController _controller = AppController();
  late final Future<void> _startup = _controller.start();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppControllerScope(
      controller: _controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '毛球互传',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF157F7B),
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(centerTitle: false),
        ),
        home: HomePage(startupFuture: _startup),
      ),
    );
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found.');
    return scope!.notifier!;
  }
}
