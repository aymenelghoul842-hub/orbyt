@echo off
setlocal
cd /d "%~dp0"
set REPO=https://github.com/aymenelghoul842-hub/orbyt.git

echo.
echo === Checking project files ===
set MISSING=0
for %%i in (client server web-dist .github render.yaml Dockerfile.prebuilt README.md) do (
  if exist "%%i" (echo OK       %%i) else (echo MISSING  %%i & set MISSING=1)
)
if "%MISSING%"=="1" (
  echo.
  echo Something is missing. Extract the ZIP again with "Extraire tout" and run this file from the extracted folder.
  pause
  exit /b 1
)

where git >nul 2>&1
if errorlevel 1 (
  echo.
  echo Git is not installed. Install it from https://git-scm.com/download/win then run this file again.
  pause
  exit /b 1
)

echo.
echo === Uploading to GitHub ===
if exist client\.git rmdir /s /q client\.git
git init
git config user.name "aymenelghoul842-hub"
git config user.email "aymenelghoul842-hub@users.noreply.github.com"
git add -A
git commit -m "Orbyt full project"
git branch -M main
git remote remove origin >nul 2>&1
git remote add origin %REPO%
git push -u origin main --force
if errorlevel 1 (
  echo.
  echo Push failed. Read the message above. If a browser window opened, sign in to GitHub and run this file again.
  pause
  exit /b 1
)

echo.
echo ===============================================
echo  DONE. Next:
echo  1. Open https://github.com/aymenelghoul842-hub/orbyt/actions
echo  2. Click "Build Flutter web" then "Run workflow"
echo  3. When it is green, deploy on render.com (Blueprint)
echo ===============================================
pause
