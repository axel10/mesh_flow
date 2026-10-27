import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('MeshFlowExampleApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeshFlowExampleApp());
    expect(find.text('Vynody / MeshFlow'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
