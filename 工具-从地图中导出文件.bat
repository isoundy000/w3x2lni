@echo off
"%~dp0build\lua.exe" "%~dp0src\make.lua" "%~dp0\" "export" %1
pause
