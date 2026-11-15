@echo off
REM One-click LOCAL launcher for Windows (needs Node.js 18+ and Flutter 3.19+)
start "Orbyt Server" cmd /k "cd /d %~dp0server && npm install && npm start"
start "Orbyt Client" cmd /k "cd /d %~dp0client && flutter pub get && flutter run -d chrome"
