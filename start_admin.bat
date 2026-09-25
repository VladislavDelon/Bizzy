@echo off
rem ============================================================
rem  Bizzy Admin - локальная админка
rem  Двойной клик: читает admin\admin_config.txt, запускает
rem  flutter run -d web-server и открывает http://localhost:8787
rem ============================================================
chcp 65001 >nul
cd /d %~dp0

if not exist "admin\admin_config.txt" (
  echo.
  echo  Не найден admin\admin_config.txt
  echo.
  echo  Создайте файл admin\admin_config.txt с тремя строками:
  echo    строка 1: логин администратора
  echo    строка 2: пароль администратора
  echo    строка 3: service_role ключ Supabase
  echo.
  echo  Пример лежит в admin\admin_config.example.txt
  echo  Ключ: Supabase Dashboard -^> Project Settings -^> API -^> service_role
  echo.
  pause
  exit /b 1
)

set "ADMIN_USER="
set "ADMIN_PASS="
set "SERVICE_KEY="
for /f "usebackq delims=" %%a in ("admin\admin_config.txt") do (
  if not defined ADMIN_USER (
    set "ADMIN_USER=%%a"
  ) else if not defined ADMIN_PASS (
    set "ADMIN_PASS=%%a"
  ) else if not defined SERVICE_KEY (
    set "SERVICE_KEY=%%a"
  )
)

if not defined SERVICE_KEY (
  echo  Файл admin\admin_config.txt должен содержать 3 строки
  echo  (логин, пароль, service_role ключ^).
  pause
  exit /b 1
)

rem Flutter: ищем в PATH, иначе стандартная папка на Desktop.
set "FLUTTER=flutter"
where flutter >nul 2>nul || set "FLUTTER=%USERPROFILE%\Desktop\flutter\bin\flutter.bat"

if not exist "%FLUTTER%" (
  where flutter >nul 2>nul
  if errorlevel 1 (
    echo  Flutter не найден ни в PATH, ни в %%USERPROFILE%%\Desktop\flutter
    pause
    exit /b 1
  )
)

start "" http://localhost:8787
"%FLUTTER%" run -d web-server --web-port=8787 -t lib/admin_app.dart --dart-define=ADMIN_USER=%ADMIN_USER% --dart-define=ADMIN_PASS=%ADMIN_PASS% --dart-define=SERVICE_KEY=%SERVICE_KEY%

echo.
echo  Админка остановлена. Окно можно закрыть.
pause
