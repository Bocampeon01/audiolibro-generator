import 'package:flutter_test/flutter_test.dart';

import 'package:audiolibro_player/main.dart';

void main() {
  testWidgets('App arranca y muestra la biblioteca', (WidgetTester tester) async {
    await tester.pumpWidget(const AudiolibroApp());
    await tester.pump();

    expect(find.text('Mis audiolibros'), findsOneWidget);
  });
}
