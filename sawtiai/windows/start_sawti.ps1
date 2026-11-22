# Sawti AI - run the voice server on this Windows PC and expose it over HTTPS
# Requirements: Docker Desktop (free for personal use), internet, ~5 GB free RAM for Docker.
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Sawti AI Server"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path (Split-Path -Parent $here) "backend"
$data    = Join-Path $env:LOCALAPPDATA "SawtiAI"
New-Item -ItemType Directory -Force -Path $data | Out-Null
$keyFile = Join-Path $data "api_key.txt"
$cfExe   = Join-Path $data "cloudflared.exe"
$cfLog   = Join-Path $data "tunnel.log"

function Say($ar, $color = "White") { Write-Host $ar -ForegroundColor $color }
function Fail($ar) { Say ""; Say "✘ $ar" Red; Say ""; Read-Host "اضغط Enter للإغلاق"; exit 1 }

Say "================ صوتي AI — تشغيل الخادم ================" Cyan

# 1) Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Fail "Docker Desktop غير مثبت. ثبّته من https://www.docker.com/products/docker-desktop/ ثم أعد تشغيل الحاسوب."
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop غير مشغّل. افتحه من قائمة ابدأ وانتظر حتى يصبح جاهزاً ثم أعد تشغيل هذا الملف." }
$memBytes = [int64](docker info --format "{{.MemTotal}}")
$memGB = [math]::Round($memBytes / 1GB, 1)
Say "• الذاكرة المتاحة لـ Docker: $memGB GB"
if ($memGB -lt 5) {
  Say "⚠ المحرك يحتاج حوالي 5 GB. قد يفشل أو يتوقف. راجع خطوة زيادة الذاكرة في windows\README.md" Yellow
}

# 2) API key (same value as SAWTI_API_KEY typed in the app)
if (Test-Path $keyFile) {
  $key = (Get-Content $keyFile -Raw).Trim()
  Say "• تم تحميل مفتاح الوصول المحفوظ."
} else {
  Say ""
  Say "اكتب مفتاح الوصول (نفس كلمة السر التي ستكتبها في التطبيق):" Yellow
  $key = (Read-Host).Trim()
  if ($key.Length -lt 16) { Fail "المفتاح قصير. استخدم 16 خانة على الأقل (يُفضل 30)." }
  Set-Content -Path $keyFile -Value $key -NoNewline
  Say "• حُفظ المفتاح في $keyFile (على جهازك فقط)."
}

# 3) Image (first time: 10-20 minutes, downloads ~3 GB)
docker image inspect sawti-backend *> $null
if ($LASTEXITCODE -ne 0) {
  Say ""
  Say "• بناء الخادم لأول مرة (10–20 دقيقة، يحتاج تنزيل حوالي 3 GB)..." Cyan
  docker build -t sawti-backend "$backend"
  if ($LASTEXITCODE -ne 0) { Fail "فشل بناء الخادم. صوّر هذه الشاشة وأرسلها." }
}

# 4) Start server (only reachable from this PC; the tunnel publishes it)
docker rm -f sawti *> $null
docker run -d --name sawti --restart unless-stopped -p 127.0.0.1:7860:7860 -e SAWTI_API_KEY="$key" sawti-backend | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "تعذر تشغيل الخادم." }
Say "• الخادم يعمل. جارٍ تحميل محرك الصوت (قد يستغرق دقيقة أو أكثر)..." Cyan
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Seconds 5
  try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:7860/health" -TimeoutSec 5
    if ($h.engine_state -eq "ready") { $ready = $true; break }
    if ($h.engine_state -eq "failed") { break }
    Write-Host "." -NoNewline
  } catch { Write-Host "." -NoNewline }
}
Say ""
if (-not $ready) { docker logs --tail 40 sawti; Fail "لم يجهز المحرك. غالباً بسبب نقص الذاكرة." }
Say "✔ محرك الصوت جاهز." Green

# 5) Free HTTPS tunnel (Cloudflare quick tunnel - no account, no card)
if (-not (Test-Path $cfExe)) {
  Say "• تنزيل cloudflared (أداة النفق المجانية)..." Cyan
  Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $cfExe
}
if (Test-Path $cfLog) { Remove-Item $cfLog -Force }
$cf = Start-Process -FilePath $cfExe -ArgumentList "tunnel","--no-autoupdate","--url","http://127.0.0.1:7860","--logfile","`"$cfLog`"" -PassThru -WindowStyle Hidden
$url = $null
for ($i = 0; $i -lt 60 -and -not $url; $i++) {
  Start-Sleep -Seconds 2
  if (Test-Path $cfLog) {
    $m = Select-String -Path $cfLog -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" | Select-Object -First 1
    if ($m) { $url = $m.Matches[0].Value }
  }
}
if (-not $url) { Fail "تعذر إنشاء الرابط. تأكد من الإنترنت وأعد المحاولة." }
try { Set-Clipboard -Value $url } catch {}

Say ""
Say "==========================================================" Green
Say "  عنوان الخادم (اكتبه في التطبيق ← الإعدادات ← ربط الخادم):" Green
Say ""
Say "      $url" Yellow
Say ""
Say "  (نُسخ إلى الحافظة)  — المفتاح: نفس كلمة السر التي كتبتها" Green
Say "==========================================================" Green
Say ""
Say "اترك هذه النافذة مفتوحة والحاسوب يعمل طوال استخدامك للتطبيق."
Say "الرابط يتغير في كل مرة تشغّل فيها هذا الملف — حدّثه في التطبيق."
Say "للإيقاف: أغلق هذه النافذة أو اضغط Ctrl+C."
try {
  while (-not $cf.HasExited) { Start-Sleep -Seconds 5 }
  Say "توقف النفق. أعد تشغيل الملف." Yellow
} finally {
  if (-not $cf.HasExited) { Stop-Process -Id $cf.Id -Force }
  docker stop sawti *> $null
  Say "تم إيقاف الخادم."
}
