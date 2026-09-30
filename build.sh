#!/usr/bin/env bash
# Detener el script si ocurre algún error
set -e

echo "Descargando Flutter..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

echo "Configurando Flutter para Web..."
flutter precache --web
flutter config --enable-web

echo "Obteniendo dependencias..."
flutter pub get

echo "Compilando aplicación para Web..."
flutter build web --release