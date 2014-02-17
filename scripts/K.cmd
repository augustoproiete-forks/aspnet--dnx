@Echo OFF
:: K [command] [args]
::   command :  Required - Name of the command to execute
::   args : Optional - Any further args will be passed directly to the command.

:: e.g. To compile the app in the current folder:
::      C:\src\MyApp\>K build

SETLOCAL

SET ERRORLEVEL=

IF "%K_APPBASE%"=="" (
  SET K_APPBASE=%CD%
)

if "%TARGET_PLATFORM%" == "" (
    SET PLATFORM=x86
)

if "%TARGET_PLATFORM%" == "amd64" (
    SET PLATFORM=amd64
)

if "%TARGET_FRAMEWORK%" == "" (
    SET FRAMEWORK=net45
)

if "%TARGET_FRAMEWORK%" == "k10" (
    SET FRAMEWORK=K
)

SET LIB_PATH=%~dp0..\src\Microsoft.Net.Project\bin\Debug\%FRAMEWORK%

IF EXIST "%~dp0k-%1.cmd" (
  "%~dp0k-%1.cmd" %2 %3 %4 %5 %6 %7 %8 %9 
) ELSE (
  CALL "%~dp0KLR" --lib "%LIB_PATH%" "Microsoft.Net.Project" %*
)

exit /b %ERRORLEVEL%

ENDLOCAL