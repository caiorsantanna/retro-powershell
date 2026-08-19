// CRT fisheye para Windows Terminal — barril geometrico, vidro com cantos
// arredondados, padding verde interno, scanlines, glow de fosforo e vinheta.
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

#if WARP
    // barril por amostragem alem da borda: nada e cortado; o encolhimento do
    // conteudo abre um anel sem textura junto ao vidro — o padding interno
    cc *= 1.0 + CURVATURE * r2;
    float2 uv    = cc * 0.5 + 0.5;
    float  scanY = uv.y; // scanlines ja acompanham o warp do conteudo
#else
    float2 uv    = tex;  // texto plano: mouse e selecao batem 1:1
    float  scanY = (cc.y * (1.0 + SCANBOW * r2)) * 0.5 + 0.5;
#endif

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

    // scanlines curvadas; periodo ~4px
    float scan = 1.0 - SCANLINE * (0.5 + 0.5 * sin(scanY * Resolution.y * 1.5707963));
    color.rgb *= scan;

    // sombra de vidro: penumbra que segue o contorno arredondado da moldura
    color.rgb *= 1.0 - EDGESHADE * smoothstep(-SHADEW, 0.0, glassD);

    // vinheta: cantos mais fundos, como vidro curvo
    color.rgb *= 1.0 - VIGNETTE * r2;

    color.a = 1.0;
    return color;
}
