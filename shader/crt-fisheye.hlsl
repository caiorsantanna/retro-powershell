// CRT fisheye para Windows Terminal — barril geometrico, vidro com cantos
// arredondados, padding verde interno, scanlines, glow de fosforo, vinheta e
// reflexo de sala na face externa do vidro.
// ATENCAO ao trade-off: o hit-test do mouse usa o grid plano e nao enxerga o
// shader, entao o warp desloca a selecao em ate ~CURVATURE x meia-tela nas
// bordas. Com CURVATURE ~0.015 o desvio fica abaixo de meia linha (toleravel);
// acima de ~0.03 a selecao cai visivelmente na linha errada. WARP 0 desliga o
// barril e simula a curvatura so com scanlines vergadas (mouse perfeito) —
// nesse modo os cantos arredondados podem tapar texto do canto (sem warp nao
// ha folga), entao reduza CORNER se usar WARP 0.
// Usado via "experimental.pixelShaderPath" no settings.json.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;       // segundos desde o inicio
    float  Scale;      // fator de DPI
    float2 Resolution; // tamanho da textura em pixels
    float4 Background; // cor de fundo do perfil
};

#define WARP      1      // 1 = barril geometrico real; 0 = curvatura so ilusoria
#define CURVATURE 0.015  // intensidade do olho de peixe (ver trade-off acima);
                         // tambem dita a largura do padding verde interno
#define SCANBOW   0.08   // vergadura extra das scanlines no modo WARP 0
#define SCANLINE  0.26   // profundidade das scanlines (0 desliga)
#define SCANDRIFT 1.5    // px/s que as scanlines escorregam (0 = paradas).
                         // Num tubo real a fase da varredura nunca esta
                         // parada; scanline imovel denuncia adesivo por
                         // cima da tela. A deriva envolve em fmod(...,4),
                         // que e o periodo exato do padrao em px, entao
                         // ela roda pra sempre sem emenda visivel
#define VIGNETTE  0.20   // escurecimento dos cantos
#define GLOW      0.55   // brilho de fosforo (halo em volta das letras)
#define EDGESHADE 0.30   // sombra de vidro na moldura curva (0 desliga)
#define CORNER    48.0   // raio em px dos cantos arredondados do vidro (ate ~90
                         // cabe na folga do warp sem tapar texto do canto)
#define SHADEW    90.0   // largura em px da penumbra de vidro junto a moldura
#define BGTINT    float3(0.053, 0.168, 0.092) // verde RobCo/Fallout (#0E2B17
                         // bruto; assenta ~#0C2514 apos scanline+vinheta).
                         // Preenche o vidro E o padding interno; a moldura fora
                         // do vidro e o padding do terminal continuam pretos
// Desgaste do fosforo: modula o BGTINT p/ imitar um tubo usado (referencia:
// telas de terminal do Fallout). Os tres em 0 = verde chapado de antes.
#define BGGRAD    0.55   // gradiente vertical: topo mais claro, base mais funda
#define BGBLOB    0.90   // mancha difusa de brilho (fosforo queimado)
#define BGBLOBAT  float2(0.78, 0.25) // posicao da mancha no vidro (x, y em 0..1)
#define BGSMUDGE  0.06   // estrias horizontais suaves de desgaste

// Dois defeitos INDEPENDENTES, de proposito: numa TV velha o tremor de
// sincronismo e a barra de zumbido sao falhas distintas, com periodos
// distintos. Dispara-las juntas viraria "efeito"; separadas viram "defeito".

// (1) Jitter: tremida curta e seca do texto, rara. Evento discreto — o tempo e
// fatiado em ciclos de 1/JITRATE s, hash11(ciclo) sorteia um valor novo por
// ciclo, e so quem passa de JITODDS vira tremida.
#define JITTER    6.0  // deslocamento maximo, em pixels (0 desliga o jitter).
                       // Teto pratico: o anel de padding que o CURVATURE abre
                       // (~8px em 1080p). Acima disso a borda mostra tubo
                       // pelado em vez de texto, porque o inside zera fora da
                       // textura
#define JITRATE   0.4  // sorteios por segundo (1/JITRATE = duracao do ciclo)
#define JITODDS   0.06 // chance de um sorteio virar tremida (~1 a cada 50s)
#define JITLEN    0.18 // duracao da tremida em segundos (deixe < 1/JITRATE)
#define JITSHAKE  60.0 // trocas de posicao por segundo dentro da tremida

// (2) Barra de zumbido: faixa diagonal de estatica subindo devagar, como ripple
// da fonte vazando pro sinal. Nao sorteia nada — so varre e some. Ela mora no
// tubo, nao no texto: usa tex (coordenada do vidro), entao passa por cima do
// conteudo sem acompanhar a curvatura dele.
#define BARNOISE  0.16 // densidade da estatica na faixa (0 desliga a barra)
#define BARLIFT   0.05 // clareada do fosforo sob a faixa
#define BARPERIOD 40.0 // segundos entre uma passagem e a proxima
#define BARSWEEP  7.0  // segundos p/ atravessar; SEMPRE < BARPERIOD, senao uma
                       // passagem comeca antes da outra sair e a barra salta
#define BARW      0.05 // espessura da faixa (fracao da altura da tela)
#define BARANGLE  3.0  // inclinacao da diagonal EM GRAUS (0 = horizontal). Em
                       // graus de verdade: a conversao usa Resolution, entao o
                       // angulo nao muda quando voce redimensiona a janela

// (3) Reflexo do vidro: o VERNIZ do tubo, como em mockup de TV retro — um
// lencol de brilho cobrindo a parte superior do vidro, cuja borda inferior
// desenha um arco suave abaulado p/ baixo. Nao e a imagem de uma luminaria
// (esse caminho foi tentado e le como mancha): e o brilho da propria
// SUPERFICIE curva, entao ele segue a forma do vidro — dai a borda em domo,
// espelhando o bojo do tubo — e cobre conteudo sem cerimonia, igual nos
// mockups. Duas coisas o separam dos efeitos acima. (a) Usa tex, a coordenada
// do vidro, e nao uv: nao warpa com o barril e NAO treme junto com o jitter —
// e esse descolamento que denuncia um plano de vidro na frente do conteudo.
// (b) E somado DEPOIS das scanlines e da vinheta, porque nao e fosforo aceso:
// nao ha feixe de varredura atravessando um reflexo. E o oposto do BGBLOB e
// da barra, que entram antes justamente por serem luz nascida dentro do tubo.
#define REFLGAIN  0.06   // forca do verniz (0 desliga). E um efeito de AREA
                         // GRANDE e diluido pela largura: em janela ultrawide
                         // o mesmo ganho rende bem menos que em 16:9 (0.09
                         // sumia numa 21:9). Calibrado em simulacao offline
#define REFLDIP   0.42   // ate onde o lencol desce no ponto mais fundo do
                         // arco (fracao da altura da tela)
#define REFLBOW   0.22   // abaulamento da borda: quanto o arco sobe do centro
                         // p/ as laterais (0 = borda reta). E o que espelha o
                         // bojo do tubo
#define REFLTILT  0.05   // inclinacao da borda: positivo desce mais fundo a
                         // ESQUERDA, como nos mockups (a luz nunca vem
                         // perfeitamente de frente); 0 = simetrico
#define REFLFEATHER 0.045 // meia-altura da transicao na borda (fracao da
                         // altura): pequena = verniz recortado de mockup,
                         // grande = esfumado
#define REFLFLOOR 0.55   // brilho na borda inferior, relativo ao do topo
                         // (0..1): o lencol e mais forte no alto do bojo e
                         // esvai ao descer
#define REFLSH0   0.15   // fracao da meia-largura onde o verniz NASCE (0 =
                         // centro da tela; 1 = borda). Abaixo disso: nada
#define REFLSH1   0.55   // onde o verniz chega CHEIO. Entre SH0 e SH1 ele
                         // cresce suave — sao os OMBROS do tubo: o vidro
                         // curvo pega luz nas quinas, nunca de frente, e o
                         // texto (que vive no meio) fica 100% fora do veu
#define REFLTINT  float3(0.90, 0.97, 1.0) // branco levemente frio. Reflete na
                         // face externa e nunca passou pelo fosforo, entao nao
                         // e verde — e esse contraste de materia que faz o
                         // verniz ler como VIDRO na frente, nao tela acesa
// Calibragem do reflexo: 1 multiplica o ganho por 4 p/ enxergar bem o arco da
// borda e o alcance. O verniz e estatico, entao nao ha o que congelar — so o
// que levantar. Mesmo ciclo dos outros: mude aqui, rode install.ps1, abra aba
// nova. Commite sempre com 0.
#define REFLCAL   0

// Calibragem: 1 congela a barra no meio da tela e trava a tremida ligada, p/
// ajustar amplitude com a imagem parada; 2 encurta MUITO os intervalos, p/ ver
// os dois acontecerem sem esperar. O WT nao recarrega .hlsl em disco: mude
// aqui, rode install.ps1 e abra uma aba nova. Commite sempre com 0.
#define GLITCHFORCE 0

// A ligacao do tubo (power-on) NAO mora aqui, e nao da p/ trazer de volta: ela
// depende de saber que a sessao acabou de comecar, e este shader nao tem esse
// sinal. Time e um relogio GLOBAL que abas novas herdam ja correndo — medido
// desenhando uma regua de Time na propria tela: ela nao reinicia ao abrir aba
// nova. Quem sabe a hora do inicio e o profile, e e la que o efeito foi feito.

// Ruido pseudo-aleatorio deterministico: HLSL nao tem random(), entao a receita
// e picar um valor com sin+frac. hash11 sorteia por indice (qual ciclo dispara),
// hash21 sorteia por pixel (a neve).
float hash11(float n)  { return frac(sin(n * 12.9898) * 43758.5453); }
float hash21(float2 p) { return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

// Time cresce sem parar; num terminal aberto ha horas os produtos estouram a
// mantissa de 24 bits e o sin() degenera (os defeitos parariam ou travariam).
// Envolver num periodo de 10min mantem tudo em faixa segura, e o padrao so
// repete a cada 10min — imperceptivel.
#define WRAPT fmod(Time, 600.0)

// Jitter ligado/desligado. Sem fade: uma tremida de 0.1s que decai nao le como
// tremida, le como borrao. Ou esta tremendo, ou nao esta.
float jitterOn()
{
#if GLITCHFORCE == 1
    return 1.0;                                  // travada ligada
#else
    float T = WRAPT;
  #if GLITCHFORCE == 2
    float rate = JITRATE * 8.0;                  // intervalos bem curtos
    float odds = 0.5;
  #else
    float rate = JITRATE;
    float odds = JITODDS;
  #endif
    float cycle = floor(T * rate);
    float t     = frac(T * rate) / rate;         // segundos dentro do ciclo
    if (hash11(cycle) >= odds || t > JITLEN) return 0.0;
    return 1.0;
#endif
}

// Inclinacao da barra convertida p/ o espaco de textura (0..1 nos dois eixos,
// que NAO e quadrado): sem multiplicar pela razao de aspecto, o mesmo valor
// desenharia angulos diferentes conforme a janela fosse redimensionada.
float barTilt()
{
    return tan(radians(BARANGLE)) * (Resolution.x / Resolution.y);
}

// Posicao da barra ao longo do eixo diagonal, ou BAROFF quando ela nao esta na
// tela. Sobe: comeca abaixo da base e sai por cima.
#define BAROFF -999.0
float barPos()
{
#if GLITCHFORCE == 1
    return 0.5;                                  // congelada no meio da tela
#else
  #if GLITCHFORCE == 2
    float period = BARSWEEP + 1.0;               // uma passagem atras da outra
  #else
    float period = BARPERIOD;
  #endif
    float k = fmod(WRAPT, period) / BARSWEEP;    // 0..1 durante a varredura
    if (k > 1.0) return BAROFF;                  // intervalo entre passagens
    // quanto mais inclinada a barra, mais longe ela viaja p/ sair inteira: as
    // pontas da diagonal ficam meio tilt atras do centro nos dois extremos
    float slack = 0.5 * abs(barTilt()) + BARW;
    return (1.0 + slack) - k * (1.0 + slack * 2.0);
#endif
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    // coordenadas centradas em [-1, 1]
    float2 cc = tex * 2.0 - 1.0;
    float  r2 = dot(cc, cc);

    // vidro: retangulo da janela com cantos arredondados (SDF em pixels);
    // fora do vidro -> moldura preta, que se funde com o padding preto
    float2 halfRes = Resolution * 0.5;
    float2 qp = abs(cc) * halfRes - (halfRes - CORNER);
    float  glassD = length(max(qp, 0.0)) - CORNER; // <0 = dentro do vidro
    if (glassD > 0.0)
        return float4(0.0, 0.0, 0.0, 1.0);

    // (1) Jitter — calculado depois do vidro (a moldura e fisica e nao treme,
    // quem treme e a imagem projetada dentro dela) e ANTES do uv, porque e um
    // deslocamento de amostragem: assim o Sample, o halo e a mascara "inside"
    // ja leem a posicao deslocada. Guardado em unidades de uv (0..1) porque os
    // dois modos de WARP precisam dele: o modo 1 soma em cc (que vai de -1 a 1,
    // dai o x2), o modo 0 soma direto em tex. Sem isso, com WARP 0 so as
    // scanlines tremeriam.
    float2 jofs = 0.0;
    if (jitterOn() > 0.0)
    {
        // troca de posicao JITSHAKE vezes por segundo: um degrau novo a cada
        // passo, nao uma interpolacao — e isso que faz tremer em vez de deslizar
        float shakeStep = floor(WRAPT * JITSHAKE);
        float2 kick = float2(hash11(shakeStep * 3.0), hash11(shakeStep * 11.0)) - 0.5;
        kick.x *= 0.35;                          // vertical domina, como sync ruim
        jofs = kick * 2.0 * JITTER / Resolution;

        cc += jofs * 2.0;
        r2  = dot(cc, cc); // barril e vinheta acompanham a imagem deslocada
    }

#if WARP
    // barril por amostragem alem da borda: nada e cortado; o encolhimento do
    // conteudo abre um anel sem textura junto ao vidro — o padding interno
    cc *= 1.0 + CURVATURE * r2;
    float2 uv    = cc * 0.5 + 0.5;
    float  scanY = uv.y; // scanlines ja acompanham o warp do conteudo
#else
    float2 uv    = tex + jofs; // texto plano: mouse e selecao batem 1:1
    float  scanY = (cc.y * (1.0 + SCANBOW * r2)) * 0.5 + 0.5;
#endif

    // deriva das scanlines: 4px e o periodo exato do padrao (2pi / 1.5707963),
    // entao envolver o deslocamento em fmod(..., 4.0) devolve a fase ao ponto de
    // partida e a deriva roda indefinidamente sem salto perceptivel
    scanY += fmod(Time * SCANDRIFT, 4.0) / Resolution.y;

    // conteudo so existe dentro da textura; no anel do padding interno
    // (inside = 0) sobra apenas o verde do tubo, scanlines e sombras
    float inside = (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0)
                       ? 1.0 : 0.0;
    float4 color = shaderTexture.Sample(samplerState, uv) * inside;

    // bloom de fosforo em dois aneis: interno (2px, forte) + externo (4px, fraco)
    float2 p1 = 2.0 / Resolution;
    float2 p2 = 4.0 / Resolution;
    float3 halo = 0.0;
    halo += shaderTexture.Sample(samplerState, uv + float2( p1.x, 0.0)).rgb;
    halo += shaderTexture.Sample(samplerState, uv + float2(-p1.x, 0.0)).rgb;
    halo += shaderTexture.Sample(samplerState, uv + float2(0.0,  p1.y)).rgb;
    halo += shaderTexture.Sample(samplerState, uv + float2(0.0, -p1.y)).rgb;
    halo += shaderTexture.Sample(samplerState, uv + float2( p1.x,  p1.y)).rgb * 0.7;
    halo += shaderTexture.Sample(samplerState, uv + float2(-p1.x,  p1.y)).rgb * 0.7;
    halo += shaderTexture.Sample(samplerState, uv + float2( p1.x, -p1.y)).rgb * 0.7;
    halo += shaderTexture.Sample(samplerState, uv + float2(-p1.x, -p1.y)).rgb * 0.7;
    halo += shaderTexture.Sample(samplerState, uv + float2( p2.x, 0.0)).rgb * 0.5;
    halo += shaderTexture.Sample(samplerState, uv + float2(-p2.x, 0.0)).rgb * 0.5;
    halo += shaderTexture.Sample(samplerState, uv + float2(0.0,  p2.y)).rgb * 0.5;
    halo += shaderTexture.Sample(samplerState, uv + float2(0.0, -p2.y)).rgb * 0.5;
    // tinta esverdeada no halo, como fosforo vazando p/ os vizinhos; mascarado
    // pelo inside p/ o sampler clamp nao borrar glifos da borda no padding
    color.rgb += (halo / 8.8) * GLOW * float3(0.75, 1.0, 0.82) * inside;

    // fundo verde do tubo, somado ANTES de scanlines/sombras/vinheta para ser
    // modulado por elas como material aceso — cobre conteudo e padding interno.
    // O desgaste usa as coordenadas do vidro (tex), nao do conteudo warpado:
    // a mancha e as estrias pertencem ao tubo fisico, nao ao texto
    float3 tube = BGTINT;
    tube *= 1.0 - BGGRAD * (tex.y - 0.35);
    float2 blobD = tex - BGBLOBAT;
    tube += BGTINT * BGBLOB * exp(-dot(blobD, blobD) * 9.0);
    tube *= 1.0 + BGSMUDGE * sin(tex.y * 41.0) * sin(tex.y * 13.0 + 2.0);
    color.rgb += tube;

    // (2) Barra de zumbido — somada depois do tubo e antes das scanlines, p/ ser
    // modulada por elas e pela vinheta como fosforo aceso, igual ao fundo. O
    // eixo e diagonal: tex.y inclinado por tex.x. A estatica usa pos.xy (espaco
    // de tela), nao uv, porque o chuvisco nasce no tubo e nao treme com a imagem
    float bp = barPos();
    if (bp > BAROFF + 1.0)
    {
        float axis = tex.y + (tex.x - 0.5) * barTilt();
        float band = 1.0 - smoothstep(0.0, BARW, abs(axis - bp)); // 1 no centro
        band *= band;                            // borda mais macia
        if (band > 0.001)
        {
            // frac antes da escala: o offset muda a cada frame mas fica preso
            // em [0,64), senao o argumento do sin cresce com o tempo e a
            // estatica congela
            float2 tofs = frac(float2(Time * 91.7, Time * 57.3)) * 64.0;
            float grain = hash21(floor(pos.xy) + tofs);
            grain = grain * grain * grain * 3.0;  // cubo = pontos esparsos
            color.rgb += (grain * BARNOISE + BARLIFT) * band
                         * float3(0.75, 1.0, 0.82);
        }
    }

    // scanlines curvadas; periodo ~4px
    float scan = 1.0 - SCANLINE * (0.5 + 0.5 * sin(scanY * Resolution.y * 1.5707963));
    color.rgb *= scan;

    // sombra de vidro: penumbra que segue o contorno arredondado da moldura
    color.rgb *= 1.0 - EDGESHADE * smoothstep(-SHADEW, 0.0, glassD);

    // vinheta: cantos mais fundos, como vidro curvo
    color.rgb *= 1.0 - VIGNETTE * r2;

    // (3) Reflexo do vidro — ultima camada, ja fora do tubo: nada aqui usa uv,
    // porque isto e a superficie do vidro e nao a imagem projetada atras dela.
    // Sem fade junto a moldura: o verniz encosta nela, e o corte do vidro com
    // cantos arredondados apara o que passar, como a moldura real.
    if (REFLGAIN > 0.0) // literal: o compilador dobra isso, REFLGAIN 0 nao custa
    {
        // borda inferior do lencol: parabola abaulada p/ baixo + inclinacao.
        // Em tex puro, SEM correcao de aspecto, de proposito: o verniz segue a
        // proporcao do vidro (como o desenho de um mockup), nao uma forma
        // fisica redonda — esticar a janela estica o verniz junto
        float t  = tex.x * 2.0 - 1.0;                // -1 (esq) .. +1 (dir)
        float yb = REFLDIP - REFLBOW * t * t - REFLTILT * t;

        // 1 acima da borda, 0 abaixo, com transicao macia de 2*REFLFEATHER
        float refl = 1.0 - smoothstep(yb - REFLFEATHER, yb + REFLFEATHER, tex.y);

        // esvai ao descer: pleno no topo do bojo, REFLFLOOR junto a borda
        refl *= lerp(1.0, REFLFLOOR, saturate(tex.y / max(yb, 1e-4)));

        // so os ombros: t ja e -1..+1, abs(t) e a distancia ao centro. No
        // miolo (abs < SH0) o verniz e ZERO — nenhum veu sobre o texto —
        // e ele nasce suave dali ate encher nas quinas superiores
        refl *= smoothstep(REFLSH0, REFLSH1, abs(t));
#if REFLCAL
        refl *= 4.0;                                 // calibragem: arco visivel
#endif
        color.rgb += refl * REFLGAIN * REFLTINT;
    }

    color.a = 1.0;
    return color;
}
