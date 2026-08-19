# Som de boot: abre e TOCA ja na primeira linha do profile, p/ o audio comecar
# imediatamente e bufferizar em paralelo com o resto do carregamento (oh-my-posh,
# players de tecla). O bloco "Boot retro" no fim so acompanha ate o som acabar.
if (Test-Path "$HOME\terminal-sounds\boot.wav") {
    Add-Type -AssemblyName PresentationCore
    $global:__bootSnd = [System.Windows.Media.MediaPlayer]::new()
    $global:__bootSnd.Volume = 1.0
    $global:__bootSnd.Open([Uri]"$HOME\terminal-sounds\boot.wav")
    $global:__bootSnd.Play()
}

oh-my-posh init pwsh --config ~/fallout.omp.json | Invoke-Expression

# Diretorios do Get-ChildItem como texto azul-claro em vez de tarja com fundo azul
# (o padrao e fundo azul + negrito, que fica ilegivel com scheme escuro)
$PSStyle.FileInfo.Directory = $PSStyle.Foreground.BrightBlue + $PSStyle.Bold

# Banner de boot estilo Fallout. O Clear-Host apaga o banner de versao do pwsh
# e o aviso de update; a mensagem de tempo de load some via -NoLogo no Terminal.
Clear-Host
$bootLines = @(
    'TALK COMMUNICATIONS UNIFIED OPERATING SYSTEM'
    'COPYRIGHT 2075-2077 TALK COMMUNICATIONS'
    "-SERVER $env:COMPUTERNAME-"
)
$bootWidth = $Host.UI.RawUI.WindowSize.Width
Write-Host ''
foreach ($line in $bootLines) {
    $pad = [Math]::Max(0, [int](($bootWidth - $line.Length) / 2))
    Write-Host ((' ' * $pad) + $line) -ForegroundColor Green
}
Write-Host ''
Remove-Variable bootLines, bootWidth, line -ErrorAction SilentlyContinue

# Som de teclado mecanico por tecla (pack Mechvibes "Model F XT", IBM 1981):
# cada tecla toca a gravacao DELA (~\terminal-sounds\key<scancode>.wav, fatiados
# do pack pelos offsets do config.json). Teclas que nao existiam no Model F
# (ç do ABNT2, vogais acentuadas) usam o som da tecla na mesma posicao fisica
# do layout US. MediaPlayer (WASAPI) com 2 vozes por tecla: sons sobrepoem em
# digitacao rapida (PlaySound/SoundPlayer cortava o click anterior).
# Enable-KeyClick / Disable-KeyClick / Set-KeyClickVolume controlam na sessao.
if ((Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) -and
    (Test-Path "$HOME\terminal-sounds\key30.wav")) {
    Add-Type -AssemblyName PresentationCore

    # mapa char -> scancode XT (posicao fisica no layout US)
    $kmap = @{}
    foreach ($row in @(
        @('1234567890', 2), @('!@#$%^&*()', 2),
        @('qwertyuiop', 16), @('QWERTYUIOP', 16),
        @('asdfghjkl', 30), @('ASDFGHJKL', 30),
        @('zxcvbnm', 44), @('ZXCVBNM', 44)
    )) {
        for ($i = 0; $i -lt $row[0].Length; $i++) { $kmap[$row[0][$i]] = $row[1] + $i }
    }
    foreach ($e in @(
        @('-', 12), @('_', 12), @('=', 13), @('+', 13),
        @('[', 26), @('{', 26), @(']', 27), @('}', 27),
        @(';', 39), @(':', 39),
        # ajustes de gosto: ç soa como a tecla A; l soa como a tecla B
        @('ç', 30), @('Ç', 30), @('l', 48), @('L', 48),
        @("'", 40), @('"', 40), @('`', 41), @('~', 41),
        @('\', 43), @('|', 43),
        @(',', 51), @('<', 51), @('.', 52), @('>', 52),
        @('/', 53), @('?', 53), @(' ', 57),
        # vogais acentuadas -> tecla da vogal base
        @('á', 30), @('à', 30), @('â', 30), @('ã', 30),
        @('Á', 30), @('À', 30), @('Â', 30), @('Ã', 30),
        @('é', 18), @('ê', 18), @('É', 18), @('Ê', 18),
        @('í', 23), @('Í', 23),
        @('ó', 24), @('ô', 24), @('õ', 24), @('Ó', 24), @('Ô', 24), @('Õ', 24),
        @('ú', 22), @('ü', 22), @('Ú', 22), @('Ü', 22)
    )) { $kmap[[char]$e[0]] = $e[1] }

    # 2 vozes por tecla: cobre tecla repetida rapida (ll, ss) sem cortar o som.
    # Players nascem MUDOS: o MediaPlayer pode vazar um blip do inicio da midia
    # quando o Open() assincrono completa — 100 abrindo juntos virava uma
    # cascata de cliques fantasma no boot. O volume real e aplicado so no Play.
    # On = $false por padrao: o Mechvibes (global, mesmo pack) cobre o terminal;
    # dois motores juntos = eco. Enable-KeyClick reativa este quando preciso.
    $global:__keyClick = @{ On = $false; Volume = 0.8; Map = $kmap; Pools = @{}; Idx = @{} }
    foreach ($f in Get-ChildItem "$HOME\terminal-sounds\key*.wav") {
        $sc = [int]$f.BaseName.Substring(3)
        $pool = @()
        foreach ($j in 1..2) {
            $mp = [System.Windows.Media.MediaPlayer]::new()
            $mp.Volume = 0.0
            $mp.Open([Uri]$f.FullName)
            $pool += $mp
        }
        $global:__keyClick.Pools[$sc] = $pool
        $global:__keyClick.Idx[$sc] = 0
    }
    Remove-Variable kmap, row, e, f, sc, pool, mp, i, j -ErrorAction SilentlyContinue

    function global:Invoke-KeyClickSound([int]$ScanCode) {
        $kc = $global:__keyClick
        if (-not $kc.On) { return }
        $pool = $kc.Pools[$ScanCode]
        if (-not $pool) { return }
        $i = $kc.Idx[$ScanCode]; $kc.Idx[$ScanCode] = ($i + 1) % $pool.Count
        $p = $pool[$i]
        $p.Volume = $kc.Volume   # volume real so aqui; em repouso fica mudo
        $p.Position = [TimeSpan]::Zero; $p.Play()
    }
    function Enable-KeyClick  { $global:__keyClick.On = $true }
    function Disable-KeyClick { $global:__keyClick.On = $false }
    function Set-KeyClickVolume([ValidateRange(0.0, 1.0)][double]$Volume) {
        $global:__keyClick.Volume = $Volume
    }

    $keyClickChords = @($global:__keyClick.Map.Keys | Where-Object { $_ -ne ' ' } |
        ForEach-Object { "$_" }) + 'Spacebar'
    foreach ($chord in $keyClickChords) {
        try {
            Set-PSReadLineKeyHandler -Chord $chord -BriefDescription KeyClick -ScriptBlock {
                param($key, $arg)
                $sc = $global:__keyClick.Map[$key.KeyChar]
                if ($sc) { Invoke-KeyClickSound $sc }
                [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
            }
        } catch {} # tecla que o parser de chord rejeitar fica sem som, sem quebrar o profile
    }
    Set-PSReadLineKeyHandler -Chord Backspace -BriefDescription KeyClick -ScriptBlock {
        param($key, $arg)
        Invoke-KeyClickSound 14   # backspace real do pack
        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
    }
    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription KeyClick -ScriptBlock {
        param($key, $arg)
        Invoke-KeyClickSound 28   # enter real do pack
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($key, $arg)
    }
    Remove-Variable keyClickChords, chord -ErrorAction SilentlyContinue
}

# Boot retro: o som ja esta tocando desde a primeira linha do profile; aqui o
# spinner a moda antiga so acompanha ate ele acabar. Dobra como warm-up: os
# players de tecla terminam de bufferizar enquanto o spinner gira. O Close()
# solta o handle do wav (senao o arquivo fica travado e nao da p/ regenerar).
if ($global:__bootSnd) {
    $spin = '/', '-', '\', '|'
    $i = 0
    $t0 = [DateTime]::Now
    $skip = $false
    # gira ate o som acabar (teto de 8s caso o playback trave); Enter pula o
    # boot com um fade-out rapido no som e libera o prompt na hora
    while (([DateTime]::Now - $t0).TotalSeconds -lt 8) {
        if ($global:__bootSnd.NaturalDuration.HasTimeSpan -and
            $global:__bootSnd.Position.TotalSeconds -ge
            $global:__bootSnd.NaturalDuration.TimeSpan.TotalSeconds - 0.1) { break }
        if (-not [Console]::IsInputRedirected) {
            while ([Console]::KeyAvailable) {
                # consome a tecla (nao vaza p/ o prompt); so Enter aciona o skip
                if (([Console]::ReadKey($true)).Key -eq 'Enter') { $skip = $true }
            }
        }
        if ($skip) {
            for ($v = 9; $v -ge 0; $v--) {
                $global:__bootSnd.Volume = $v / 10.0
                Start-Sleep -Milliseconds 35
            }
            $global:__bootSnd.Stop()
            break
        }
        [Console]::Write("`r  INITIALIZING TALKLINK PROTOCOL... $($spin[$i++ % 4]) ")
        Start-Sleep -Milliseconds 80
    }
    [Console]::Write("`r  INITIALIZING TALKLINK PROTOCOL... OK`n`n")
    $global:__bootSnd.Close()
    Remove-Variable -Scope Global -Name __bootSnd -ErrorAction SilentlyContinue
    Remove-Variable spin, i, t0 -ErrorAction SilentlyContinue
}
