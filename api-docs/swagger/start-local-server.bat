@echo off
echo ========================================
echo KICC ARS API Swagger UI - Local Server
echo ========================================
echo.

REM Swagger 디렉토리로 이동
cd /d "%~dp0"

REM Python 버전 확인
python --version >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Python 발견
    echo.
    echo 로컬 서버를 시작합니다...
    echo.
    echo 브라우저에서 아래 주소로 접속하세요:
    echo http://localhost:8000/index.html
    echo.
    echo 종료하려면 Ctrl+C를 누르세요.
    echo.
    python -m http.server 8000
) else (
    echo [ERROR] Python이 설치되어 있지 않습니다.
    echo.
    echo 다음 방법 중 하나를 선택하세요:
    echo 1. Python 설치: https://www.python.org/downloads/
    echo 2. VS Code Live Server 확장 사용
    echo 3. Node.js http-server 사용: npm install -g http-server
    echo.
    pause
)
