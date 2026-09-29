// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:assetdesk_/main.dart';

void main() {
  testWidgets('Carga de pantalla principal', (WidgetTester tester) async {
    // Renderiza la aplicación con la clase correcta
    await tester.pumpWidget(const AssetDeskApp());
  });
}