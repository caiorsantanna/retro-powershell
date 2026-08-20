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

# Ligacao do tubo: antes do banner, a tela nasce preta, uma linha fina acende no
# meio e se abre na vertical, como o power-on de um CRT. Sao as duas frentes de
# varredura que se afastam; o miolo atras delas continua preto.
# Por que isto vive no profile e nao no shader: um pixel shader do Windows
# Terminal nao tem como saber que a sessao comecou. O uniform Time e um relogio
# GLOBAL, que abas novas herdam ja correndo — nao um cronometro por aba (medido
# na marra: uma regua de Time desenhada na tela nao reinicia ao abrir aba nova).
# Quem sabe a hora do inicio e este arquivo, que E o codigo que roda quando a
# aba abre. E como a tela esta vazia nesse instante, desenhar a faixa em texto e
# visualmente equivalente a comprimir a imagem: nao ha imagem. O shader ainda
# aplica halo de fosforo, scanlines e curvatura por cima, entao o brilho do tubo
# sai de graca.
if (-not [Console]::IsOutputRedirected -and
    $Host.UI.RawUI.WindowSize.Height -ge 8) {
    # SetCursorPosition usa coordenadas do BUFFER, nao da janela; com scrollback
    # os dois nao coincidem, entao tudo e ancorado no cursor pos-Clear-Host
    $tubeTop = [Console]::CursorTop
    $tubeBot = [Math]::Min($tubeTop + $Host.UI.RawUI.WindowSize.Height - 1,
                           [Console]::BufferHeight - 1)
    $tubeMid = [int](($tubeTop + $tubeBot) / 2)
    # -1 na largura: escrever na ultima celula da linha rolaria a tela
    $tubeBar = ([string][char]0x2588) * ($Host.UI.RawUI.WindowSize.Width - 1)
    $tubeGap = ' ' * ($Host.UI.RawUI.WindowSize.Width - 1)  # apaga a borda antiga
    $tubeSteps = 14
    [Console]::CursorVisible = $false

    # o filamento: uma linha so, o ponto mais quente do ciclo
    [Console]::ForegroundColor = [ConsoleColor]::White
    [Console]::SetCursorPosition(0, $tubeMid)
    [Console]::Write($tubeBar)
    Start-Sleep -Milliseconds 130

    # Abertura vertical. O que se move sao as duas FRENTES DE VARREDURA, nao uma
    # faixa preenchida: cada passo apaga as bordas antigas e redesenha nas novas
    # posicoes, entao atras delas fica preto. E o que um tubo faz de verdade —
    # preencher solido acenderia a tela inteira no meio da animacao, que e o
    # oposto de "nasce preto e vai abrindo".
    # O expoente 0.65 abre depressa no inicio e assenta no fim.
    $tubePrev = 0
    for ($tubeI = 1; $tubeI -le $tubeSteps; $tubeI++) {
        # o alcance usa a MAIOR das duas metades: com altura par a metade de
        # baixo tem uma linha a mais, e medir so pela de cima faria a borda
        # inferior parar antes da ultima linha. Os limites adiante aparam o resto
        $tubeReach = [int][Math]::Round(
            [Math]::Max($tubeMid - $tubeTop, $tubeBot - $tubeMid) *
            [Math]::Pow($tubeI / $tubeSteps, 0.65))
        if ($tubeReach -gt $tubePrev) {
            # apaga onde as bordas estavam (no 1o passo, o proprio filamento)
            foreach ($tubeR in ($tubeMid - $tubePrev), ($tubeMid + $tubePrev)) {
                if ($tubeR -ge $tubeTop -and $tubeR -le $tubeBot) {
                    [Console]::SetCursorPosition(0, $tubeR)
                    [Console]::Write($tubeGap)
                }
            }
            # redesenha nas novas; borda que ja saiu da tela simplesmente some
            foreach ($tubeR in ($tubeMid - $tubeReach), ($tubeMid + $tubeReach)) {
                if ($tubeR -ge $tubeTop -and $tubeR -le $tubeBot) {
                    [Console]::SetCursorPosition(0, $tubeR)
                    [Console]::Write($tubeBar)
                }
            }
            $tubePrev = $tubeReach
        }
        Start-Sleep -Milliseconds 26
    }
    Start-Sleep -Milliseconds 70
    [Console]::ResetColor()
    [Console]::CursorVisible = $true
    Clear-Host
    Remove-Variable tubeTop, tubeBot, tubeMid, tubeBar, tubeGap, tubeSteps,
                    tubePrev, tubeI, tubeReach, tubeR -ErrorAction SilentlyContinue
}

$bootLines = @(
    'RETROSHELL UNIFIED OPERATING SYSTEM'
    'COPYRIGHT 2075-2077 RETROSHELL INDUSTRIES'
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
        [Console]::Write("`r  INITIALIZING TERMLINK PROTOCOL... $($spin[$i++ % 4]) ")
        Start-Sleep -Milliseconds 80
    }
    [Console]::Write("`r  INITIALIZING TERMLINK PROTOCOL... OK`n`n")
    $global:__bootSnd.Close()
    Remove-Variable -Scope Global -Name __bootSnd -ErrorAction SilentlyContinue
    Remove-Variable spin, i, t0 -ErrorAction SilentlyContinue
}
