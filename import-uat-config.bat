@echo off
REM One-tap import of etc\firestore_clone_data.txt into the UAT Firestore
REM (the "uat" alias in .firebaserc = sawad-loan-universal-uat).
REM
REM Double-click this file, check the preview, then press Y to write.
REM Requires: Node 20+ and a logged-in Firebase CLI ("firebase login").

cd /d "%~dp0"
echo.
node tools\firestore-import\import-config.mjs %*
echo.
pause
