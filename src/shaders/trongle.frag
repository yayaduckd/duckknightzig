Texture2D < float4 > Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

float4 main(float2 TexCoord : TEXCOORD0, float4 color : TEXCOORD1 ): SV_Target0
{
    float4 res = color * Texture . Sample(Sampler, TexCoord);
    if (res.a < 0.1) {
        discard;
    }
    return res;

}
