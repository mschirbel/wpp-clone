param(
  [Parameter(Mandatory=$true)]
  [string]$RepoName,

  [ValidateSet("public","private")]
  [string]$Visibility = "public",

  [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Require-Command($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "Erro: '$cmd' não encontrado. $hint" -ForegroundColor Red
    exit 1
  }
}

function Run($exe, [string[]]$args) {
  & $exe @args
  return $LASTEXITCODE
}

Require-Command git "Instale o Git e reabra o PowerShell."
Require-Command gh  "Instale o GitHub CLI (gh) e reabra o PowerShell."

if (-not (Test-Path ".\index.html")) {
  Write-Host "Erro: index.html não encontrado na pasta atual." -ForegroundColor Red
  Write-Host "Entre na pasta do projeto (cd ...) e rode novamente."
  exit 1
}

# Checar login do GH
Run gh @("auth","status") | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Você não está logado no GitHub CLI." -ForegroundColor Yellow
  Write-Host "Rode: gh auth login"
  exit 1
}

# Descobrir owner
$Owner = (gh api user -q ".login").Trim()
$RemoteUrl = "https://github.com/$Owner/$RepoName.git"
$FullRepo = "$Owner/$RepoName"

# Init git se precisar
if (-not (Test-Path ".\.git")) {
  Run git @("init") | Out-Null
}

# Garantir branch main
Run git @("checkout","-B",$Branch) | Out-Null

# .gitignore básico
if (-not (Test-Path ".\.gitignore")) {
@"
.DS_Store
Thumbs.db
node_modules/
"@ | Set-Content -Encoding utf8 .gitignore
}

# Stage
Run git @("add",".") | Out-Null

# Ver se existe algo staged
Run git @("diff","--cached","--quiet") | Out-Null
$HasStaged = ($LASTEXITCODE -ne 0)  # 1 = tem diff staged

# Ver se existe HEAD (repo novo não tem)
Run git @("rev-parse","--verify","HEAD") | Out-Null
$HasHead = ($LASTEXITCODE -eq 0)

if (-not $HasHead -or $HasStaged) {
  # Faz commit inicial ou commit de mudanças
  Run git @("commit","-m","Deploy initial static site") | Out-Null
}

# Repo existe no GitHub?
Run gh @("repo","view",$FullRepo) | Out-Null
$RepoExists = ($LASTEXITCODE -eq 0)

if (-not $RepoExists) {
  Write-Host "Criando repo no GitHub: $FullRepo ($Visibility)..." -ForegroundColor Cyan
  $visFlag = if ($Visibility -eq "public") { "--public" } else { "--private" }
  Run gh @("repo","create",$FullRepo,$visFlag,"--confirm") | Out-Null
}

# Garantir remote origin configurado corretamente
Run git @("remote","get-url","origin") | Out-Null
$HasOrigin = ($LASTEXITCODE -eq 0)

if (-not $HasOrigin) {
  Run git @("remote","add","origin",$RemoteUrl) | Out-Null
} else {
  # Ajusta origin caso esteja apontando pra outro lugar
  $current = (git remote get-url origin).Trim()
  if ($current -ne $RemoteUrl) {
    Run git @("remote","set-url","origin",$RemoteUrl) | Out-Null
  }
}

# Push
Write-Host "Fazendo push para origin/$Branch..." -ForegroundColor Cyan
Run git @("push","-u","origin",$Branch) | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Erro no push. Verifique se você tem permissão no repo e se o repo foi criado." -ForegroundColor Red
  exit 1
}

# Habilitar Pages (root)
Write-Host "Habilitando GitHub Pages..." -ForegroundColor Cyan

# Tenta criar pages
Run gh @("api","-X","POST","repos/$Owner/$RepoName/pages","-f","source[branch]=$Branch","-f","source[path]=/") | Out-Null
if ($LASTEXITCODE -ne 0) {
  # Se já existe, tenta update
  Run gh @("api","-X","PUT","repos/$Owner/$RepoName/pages","-f","source[branch]=$Branch","-f","source[path]=/") | Out-Null
}

$PagesUrl = "https://$Owner.github.io/$RepoName/"
Write-Host ""
Write-Host "✅ Pronto!" -ForegroundColor Green
Write-Host "Repo:  https://github.com/$Owner/$RepoName"
Write-Host "Pages: $PagesUrl"
Write-Host ""
Write-Host "Se abrir sem CSS: Ctrl+Shift+R (hard refresh)." -ForegroundColor DarkGray
