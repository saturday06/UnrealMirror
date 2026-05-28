@echo off
setlocal

cd /d "%~dp0.."

echo Formatting C# files...
dotnet tool run csharpier format .

echo Formatting C/C++ files...
for /r %%f in (*.c *.cpp *.h) do (
  echo Formatting: %%f
  clang-format -i "%%f"
)

endlocal
