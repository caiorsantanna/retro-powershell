# retro-powershell

PowerShell com cara de terminal Fallout: shader CRT (curvatura de tubo, scanlines,
fósforo verde desgastado), banner de boot da **TALK COMMUNICATIONS UNIFIED OPERATING
SYSTEM** com som de inicialização e spinner à moda antiga, prompt oh-my-posh temático
e som de teclado mecânico **IBM Model F XT (1981)** em todo o Windows via Mechvibes.

## Requisitos

| O quê | Como instalar | Para quê |
|---|---|---|
| [oh-my-posh](https://ohmyposh.dev) | `winget install JanDeDobbeleer.OhMyPosh` | o prompt temático |
| [Mechvibes](https://mechvibes.com) | baixar e instalar pelo site (o instalador não roda silencioso via winget) | som de teclas global, em qualquer app |
| PowerShell 7+ | `winget install Microsoft.PowerShell` | o profile usa recursos do pwsh |
| Windows Terminal | já vem no Windows 11 | shader CRT e profile TALKOS |
| MesloLGM Nerd Font | `oh-my-posh font install meslo` | glifos do prompt |

## Instalação

```powershell
git clone https://github.com/caiorsantanna/retro-powershell.git
cd retro-powershell
.\install.ps1
```

O instalador é **idempotente** (rode de novo após um `git pull` para atualizar) e faz
**backup** de tudo o que toca (sufixo `.bak-retro`). Ele:

1. Copia os 50 sons de tecla + som de boot para `~\terminal-sounds`;
2. Copia o shader `crt-fisheye.hlsl` e o tema `fallout.omp.json` para `~`;
3. Instala o profile do PowerShell (`$PROFILE`);
4. Faz *merge* no `settings.json` do Windows Terminal: adiciona o scheme **Fallout**
   e o profile **TALKOS** (com `-NoLogo`), define-o como default, maximizado, no
   monitor secundário **se houver um conectado** (detectado na hora);
5. Instala o soundpack **Model F XT** na pasta custom do Mechvibes e registra o
   Mechvibes para iniciar com o Windows.

Depois da instalação, selecione o pack **Model_F_XT** na interface do Mechvibes
(ícone na bandeja) — esse passo é manual, o app não expõe config por arquivo.

## O que tem dentro

```
profile/    Microsoft.PowerShell_profile.ps1 — banner, boot com som + spinner
            (Enter pula com fade-out), motor de cliques por tecla no PSReadLine
            (desligado por padrão; Enable-KeyClick liga)
theme/      fallout.omp.json — prompt verde-fósforo de duas linhas
shader/     crt-fisheye.hlsl — barril geométrico, scanlines, vinheta, fundo de
            fósforo desgastado (knobs comentados no topo do arquivo)
terminal/   scheme Fallout + profile TALKOS (fragmentos que o installer mescla)
sounds/     key<scancode>.wav (50 teclas fatiadas do pack) + boot.wav
mechvibes/  o pack Model F XT pronto pra pasta custom do Mechvibes
```

## Comandos no dia a dia

- `Enable-KeyClick` / `Disable-KeyClick` — liga/desliga os cliques do próprio
  terminal (útil quando o Mechvibes não estiver rodando; com ele rodando, deixe
  desligado para não ter eco duplo);
- `Set-KeyClickVolume 0.5` — volume dos cliques do terminal (0.0 a 1.0);
- **Enter durante o boot** — pula o som com fade-out e libera o prompt;
- `F11` — alterna tela cheia no Windows Terminal.

## Créditos dos sons

- Soundpack **Model F XT** para Mechvibes, por *Rezenee* (comunidade Mechvibes);
- Som de boot derivado de ["computer startup" (freesound #6331)](https://pixabay.com/sound-effects/)
  da comunidade freesound (primeiros 6s, +10dB, fades).
