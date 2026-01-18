param(
  [Parameter(Mandatory=$true)]
  [string]$RepoName,

  [ValidateSet("public","private")]
  [string]$Visibility = "public",

  [string]$Branch = "main"
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Require-Command($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "Erro: '$cmd' não encontrado. $hint" -ForegroundColor Red
    exit 1
  }
}

function Run-Capture([string]$exe, [string[]]$argv) {
  # Evita NativeCommandError quando um comando escreve no stderr mas sai com 0
  $oldPref = $global:ErrorActionPreference
  $global:ErrorActionPreference = "SilentlyContinue"
  $out = & $exe @argv 2>&1
  $code = $LASTEXITCODE
  $global:ErrorActionPreference = $oldPref

  return [pscustomobject]@{ Code = $code; Output = $out }
}

Require-Command git "Instale o Git e reabra o PowerShell."
Require-Command gh  "Instale o GitHub CLI (gh) e reabra o PowerShell."

if (-not (Test-Path ".\index.html")) {
  Write-Host "Erro: index.html não encontrado na pasta atual." -ForegroundColor Red
  exit 1
}

# Login gh
$r = Run-Capture "gh" @("auth","status")
if ($r.Code -ne 0) {
  Write-Host "Você não está logado no GitHub CLI. Rode: gh auth login" -ForegroundColor Yellow
  Write-Host ($r.Output -join "`n")
  exit 1
}

$Owner = (gh api user -q ".login").Trim()
$FullRepo = "$Owner/$RepoName"
$RemoteHttps = "https://github.com/$FullRepo.git"

# Init git
if (-not (Test-Path ".\.git")) {
  Run-Capture "git" @("init") | Out-Null
}

# Branch
Run-Capture "git" @("checkout","-B",$Branch) | Out-Null

# .gitignore
if (-not (Test-Path ".\.gitignore")) {
@"
.DS_Store
Thumbs.db
node_modules/
"@ | Set-Content -Encoding utf8 .gitignore
}

# Stage
Run-Capture "git" @("add",".") | Out-Null

# HEAD existe?
$hasHead = ((Run-Capture "git" @("rev-parse","--verify","HEAD")).Code -eq 0)

# Tem diff staged?
$diffStaged = Run-Capture "git" @("diff","--cached","--quiet")
$hasStaged = ($diffStaged.Code -ne 0)

if (-not $hasHead -or $hasStaged) {
  $c = Run-Capture "git" @("commit","-m","Deploy initial static site")
  if ($c.Code -ne 0) {
    Write-Host "Erro ao commitar. Saída:" -ForegroundColor Red
    Write-Host ($c.Output -join "`n")
    Write-Host ""
    Write-Host 'Se reclamar de user.name/email:' -ForegroundColor Yellow
    Write-Host 'git config --global user.name "Seu Nome"' -ForegroundColor Yellow
    Write-Host 'git config --global user.email "seuemail@exemplo.com"' -ForegroundColor Yellow
    exit 1
  }
}

# Repo existe?
$view = Run-Capture "gh" @("repo","view",$FullRepo)
if ($view.Code -ne 0) {
  Write-Host "Criando repo no GitHub: $FullRepo ($Visibility)..." -ForegroundColor Cyan
  $visFlag = if ($Visibility -eq "public") { "--public" } else { "--private" }
  $cr = Run-Capture "gh" @("repo","create",$FullRepo,$visFlag,"--confirm")
  if ($cr.Code -ne 0) {
    Write-Host "Erro ao criar repo. Saída:" -ForegroundColor Red
    Write-Host ($cr.Output -join "`n")
    exit 1
  }
}

# Origin (FORÇA HTTPS)
$origin = Run-Capture "git" @("remote","get-url","origin")
if ($origin.Code -ne 0) {
  Run-Capture "git" @("remote","add","origin",$RemoteHttps) | Out-Null
} else {
  Run-Capture "git" @("remote","set-url","origin",$RemoteHttps) | Out-Null
}

Write-Host "Origin: $RemoteHttps" -ForegroundColor DarkGray

# Push
Write-Host "Fazendo push para origin/$Branch..." -ForegroundColor Cyan
$p = Run-Capture "git" @("push","-u","origin",$Branch)
if ($p.Code -ne 0) {
  Write-Host "❌ Erro no push. Saída completa:" -ForegroundColor Red
  Write-Host ($p.Output -join "`n")
  Write-Host ""
  Write-Host "Dica: rode: gh auth setup-git" -ForegroundColor Yellow
  exit 1
}

# Pages
Write-Host "Habilitando GitHub Pages..." -ForegroundColor Cyan
$createPages = Run-Capture "gh" @("api","-X","POST","repos/$Owner/$RepoName/pages","-f","source[branch]=$Branch","-f","source[path]=/")
if ($createPages.Code -ne 0) {
  $updatePages = Run-Capture "gh" @("api","-X","PUT","repos/$Owner/$RepoName/pages","-f","source[branch]=$Branch","-f","source[path]=/")
  if ($updatePages.Code -ne 0) {
    Write-Host "Aviso: não consegui habilitar Pages via API. Saída:" -ForegroundColor Yellow
    Write-Host ($updatePages.Output -join "`n")
  }
}

$PagesUrl = "https://$Owner.github.io/$RepoName/"
Write-Host ""
Write-Host "✅ Pronto!" -ForegroundColor Green
Write-Host "Repo:  https://github.com/$Owner/$RepoName"
Write-Host "Pages: $PagesUrl"
