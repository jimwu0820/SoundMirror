@echo off
title SoundMirror
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sound-mirror.ps1"
