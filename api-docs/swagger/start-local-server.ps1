# KICC ARS API Swagger UI - Local Server (PowerShell)
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "KICC ARS API Swagger UI - Local Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Swagger 디렉토리로 이동
Set-Location $PSScriptRoot

# Python 확인
$pythonInstalled = $null -ne (Get-Command python -ErrorAction SilentlyContinue)

if ($pythonInstalled) {
    Write-Host "[OK] Python 발견" -ForegroundColor Green
    Write-Host ""
    Write-Host "로컬 서버를 시작합니다..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "브라우저에서 아래 주소로 접속하세요:" -ForegroundColor White
    Write-Host "http://localhost:8000/index.html" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "종료하려면 Ctrl+C를 누르세요." -ForegroundColor Yellow
    Write-Host ""

    # 브라우저 자동 열기 (5초 후)
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:8000/index.html"

    # Python HTTP 서버 실행
    python -m http.server 8000
} else {
    Write-Host "[ERROR] Python이 설치되어 있지 않습니다." -ForegroundColor Red
    Write-Host ""
    Write-Host "다음 방법 중 하나를 선택하세요:" -ForegroundColor Yellow
    Write-Host "1. Python 설치: https://www.python.org/downloads/" -ForegroundColor White
    Write-Host "2. VS Code Live Server 확장 사용" -ForegroundColor White
    Write-Host "3. Node.js http-server 사용: npm install -g http-server" -ForegroundColor White
    Write-Host ""
    Read-Host "계속하려면 Enter를 누르세요"
}
