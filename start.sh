#!/usr/bin/env bash
# Local launcher for macOS / Linux (needs Node.js 18+ and Flutter 3.19+)
set -e
cd "$(dirname "$0")"
(cd server && npm install && npm start) &
(cd client && flutter pub get && flutter run -d chrome)
