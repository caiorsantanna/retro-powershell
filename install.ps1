#Requires -Version 7
# Instala o tema retro (Fallout/CRT) do PowerShell nesta maquina.
# Idempotente: pode rodar de novo apos um git pull para atualizar tudo.
# Faz backup do profile e do settings.json do Windows Terminal antes de mexer.

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

function Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------- pre-requisitos
Step 'Conferindo pre-requisitos'
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Warn 'oh-my-posh nao encontrado. Instale com:  winget install JanDeDobbeleer.OhMyPosh'
    Warn 'O prompt vai quebrar sem ele. Instale e rode este script de novo.'
}
Add-Type -AssemblyName System.Drawing
$fontOk = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name |
    Where-Object { $_ -like 'MesloLGM*' }
if (-not $fontOk) {
    Warn 'Fonte MesloLGM Nerd Font nao encontrada. Instale com:  oh-my-posh font install meslo'
}
$mechvibesExe = "$env:LOCALAPPDATA\Programs\Mechvibes\Mechvibes.exe"
if (-not (Test-Path $mechvibesExe)) {
    Warn 'Mechvibes nao encontrado (o som global de teclas fica sem efeito ate instalar).'
    Warn 'Baixe em https://mechvibes.com e rode este script de novo para configurar o pack.'
}

# ---------------------------------------------------------------------- arquivos
Step 'Copiando sons para ~\terminal-sounds'
New-Item -ItemType Directory -Force "$HOME\terminal-sounds" | Out-Null
# copia arquivo a arquivo: sessoes abertas do terminal seguram handle nos wavs
# (players do profile); identicos sao pulados, travados viram aviso — o boot e
# as teclas continuam funcionando com a versao que ja esta la
$locked = 0
foreach ($f in Get-ChildItem "$repo\sounds\*.wav") {
    $dst = "$HOME\terminal-sounds\$($f.Name)"
    if ((Test-Path $dst) -and
        (Get-FileHash $dst).Hash -eq (Get-FileHash $f.FullName).Hash) { continue }
    try { Copy-Item $f.FullName $dst -Force }
    catch { $locked++ }
}
if ($locked) {
    Warn "$locked som(ns) em uso por um terminal aberto ficaram na versao antiga."
    Warn 'Feche as janelas do terminal e rode o script de novo para atualiza-los.'
}

Step 'Copiando shader CRT e tema do oh-my-posh para ~'
Copy-Item "$repo\shader\crt-fisheye.hlsl" "$HOME\crt-fisheye.hlsl" -Force
Copy-Item "$repo\theme\fallout.omp.json" "$HOME\fallout.omp.json" -Force

Step "Instalando profile do PowerShell em $PROFILE"
New-Item -ItemType Directory -Force (Split-Path $PROFILE) | Out-Null
if ((Test-Path $PROFILE) -and
    (Get-Item $PROFILE).Length -ne (Get-Item "$repo\profile\Microsoft.PowerShell_profile.ps1").Length) {
    Copy-Item $PROFILE "$PROFILE.bak-retro" -Force
    Warn "Profile existente salvo em $PROFILE.bak-retro"
}
Copy-Item "$repo\profile\Microsoft.PowerShell_profile.ps1" $PROFILE -Force

# -------------------------------------------------------------- windows terminal
Step 'Configurando Windows Terminal (merge no settings.json)'
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path $wt)) {
    Warn 'settings.json do Windows Terminal nao encontrado — instale o Windows Terminal e rode de novo.'
} else {
    Copy-Item $wt "$wt.bak-retro" -Force
    $s = Get-Content $wt -Raw | ConvertFrom-Json

    # scheme Fallout (adiciona se nao existir)
    $scheme = Get-Content "$repo\terminal\fallout-scheme.json" -Raw | ConvertFrom-Json
    if ($null -eq $s.schemes) { $s | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force }
    if (-not ($s.schemes | Where-Object name -eq $scheme.name)) { $s.schemes = @($s.schemes) + $scheme }

    # profile RetroShell (substitui por guid se ja existir; shader aponta p/ o $HOME local)
    $retro = Get-Content "$repo\terminal\retroshell-profile.json" -Raw | ConvertFrom-Json
    $retro.'experimental.pixelShaderPath' = "$HOME\crt-fisheye.hlsl"
    $s.profiles.list = @($s.profiles.list | Where-Object guid -ne $retro.guid) + $retro

    # fonte padrao dos profiles (a MesloLGM precisa estar instalada)
    if ($null -eq $s.profiles.defaults) {
        $s.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $s.profiles.defaults.font) {
        $s.profiles.defaults | Add-Member -NotePropertyName font `
            -NotePropertyValue ([pscustomobject]@{ face = 'MesloLGM Nerd Font' }) -Force
    }

    # launch: RetroShell como default, maximizado, no monitor secundario se houver
    $s.defaultProfile = $retro.guid
    $s | Add-Member -NotePropertyName launchMode -NotePropertyValue 'maximized' -Force
    Add-Type -AssemblyName System.Windows.Forms
    $second = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
    if ($second) {
        # um ponto folgado dentro do monitor secundario; o Terminal maximiza no
        # monitor que contem o ponto e cai no primario se ele nao estiver ligado
        $pos = "$($second.Bounds.X + 100),$($second.Bounds.Y + 100)"
        $s | Add-Member -NotePropertyName initialPosition -NotePropertyValue $pos -Force
        Write-Host "    monitor secundario detectado: initialPosition = $pos"
    }

    $s | ConvertTo-Json -Depth 64 | Set-Content $wt -Encoding UTF8
    Write-Host "    backup do settings.json em $wt.bak-retro"
}

# -------------------------------------------------------------------- mechvibes
if (Test-Path $mechvibesExe) {
    Step 'Instalando soundpack Model F XT no Mechvibes + inicio com o Windows'
    $mvCustom = "$env:APPDATA\Mechvibes\custom\model-f-xt"
    New-Item -ItemType Directory -Force $mvCustom | Out-Null
    Copy-Item "$repo\mechvibes\model-f-xt\*" $mvCustom -Force
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'Mechvibes' -Value "`"$mechvibesExe`""
    # NAO iniciar o Mechvibes daqui: processo filho do console morre junto com o
    # terminal. Abrir/reabrir e passo manual (a pasta custom so e lida no boot
    # do app, entao um Mechvibes ja aberto precisa ser fechado e reaberto).
    if (Get-Process mechvibes -ErrorAction SilentlyContinue) {
        Warn 'Mechvibes esta aberto: feche e abra de novo para ele enxergar o pack.'
    } else {
        Warn 'Abra o Mechvibes manualmente (menu Iniciar) para ativar o pack.'
    }
}

# ---------------------------------------------------------------------- resumo
Step 'Pronto! Passos manuais que restam:'
Write-Host @'
  1. Abra uma aba nova do Windows Terminal (profile RetroShell) e curta o boot.
     - Enter durante o spinner pula o boot com fade-out.
  2. Abra o Mechvibes pelo menu Iniciar (se ja estava aberto, feche e abra de novo)
     e selecione o pack "Model_F_XT" na interface; ajuste o volume ali.
  3. Se o prompt aparecer sem icones/glifos, instale a fonte:  oh-my-posh font install meslo
     (e confira se o profile RetroShell esta usando "MesloLGM Nerd Font").

  Rollback: os backups ficam ao lado dos originais com sufixo .bak-retro.
'@
