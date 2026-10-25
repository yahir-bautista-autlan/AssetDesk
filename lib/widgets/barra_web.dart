import 'dart:js_interop';

@JS('colorBarraSuperior')
external void _colorBarraSuperior(JSString color);

void aplicarColorBarra(String color) {
  try {
    _colorBarraSuperior(color.toJS);
  } catch (_) {}
}