@echo off
title StreamKeep by Nirlicnick

:: Check if setup has been run (look for signed scripts)
powershell -Command "if (-not (Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue)) { exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo  StreamKeep - First Time Setup
    echo  ================================
    echo  Running setup before launching...
    echo.
    powershell -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
)

:: Launch the GUI
echo.
echo  Starting StreamKeep GUI...
python "%~dp0StreamKeep.py"

:: If python fails try py launcher
if %errorlevel% neq 0 (
    py "%~dp0StreamKeep.py"
)

if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Could not launch StreamKeep.
    echo  Make sure Python is installed: https://python.org
    echo.
    pause
)
