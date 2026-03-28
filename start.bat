@echo off
echo Starting VoiceClaw Backend Server...
start "VoiceClaw Backend" cmd /k "python server.py"

echo Starting VoiceClaw Frontend (Vite React)...
start "VoiceClaw Frontend" cmd /k "cd frontend && npm run dev"

echo Both servers are starting in separate windows.
echo Close the command windows to stop the servers.
