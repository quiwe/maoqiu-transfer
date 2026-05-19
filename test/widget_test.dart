import 'package:flutter_test/flutter_test.dart';
import 'package:maoqiu_transfer/app.dart';

void main() {
  testWidgets('app widget can be constructed', (tester) async {
    await tester.pumpWidget(const MaoQiuTransferApp());
    expect(find.text('毛球互传'), findsOneWidget);
  });
}
