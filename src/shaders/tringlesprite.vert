// chi3svs vert 0 0 0 1 //chi3sfs frag 1 0 0 0

struct SpriteParams {
    float3 position;
    float  rotation;
    float4 source_rect;
    float4 color;
    float2 origin;
    float2 scale;
};

struct VertexParams {
    uint instance_id : SV_InstanceID;
    uint vertex_id : SV_VertexID;
};

struct VertexOut {
    float4 pos : SV_POSITION0;
    float2 uv : TEXCOORD0;
    float4 color : TEXCOORD1;
};

// struct Constants {
//     float4x4 vp;
//     Sprite *sprites;
// };
cbuffer UniformBlock : register(b0, space1)
{
    float4x4 vp;
    // float4x4 MatrixTransform : packoffset(c0);
};

StructuredBuffer<SpriteParams> sps : register(t0, space0);    //


struct Fragment {
    float4 color : SV_Target;
};

// [[vk::binding(0, 0)]]
// Sampler2D tex;

// [shader("vertex")]
VertexOut main(VertexParams vertex_params) {


    float4x4 ViewProjection = vp;
    SpriteParams sprite = sps[vertex_params.instance_id];
    VertexOut output;

    const float2 positions[4] = {
        float2(1.f, 1.f),
        float2(0.f, 1.f),
        float2(1.f, 0.f),
        float2(0.f, 0.f),
    };

    // -- transform
    float2 pos = positions[vertex_params.vertex_id];
    float2 origin = sprite.origin;
    float2 pos_origin = pos - sprite.origin;
    float2 pos_rotate = float2(
        pos_origin.x * cos(sprite.rotation) + pos_origin.y * -sin(sprite.rotation),
        pos_origin.x * sin(sprite.rotation) + pos_origin.y *  cos(sprite.rotation)
    );
    float2 pos_scale = sprite.scale * pos_rotate;
    float3 end_pos = sprite.position + float3(pos_scale, 0);

    // -- uvs
    float4 src = sprite.source_rect;
    const float2 uvs[4] = { src.xy, src.zy, src.xw, src.zw };

    output.pos = mul(float4(end_pos, 1.), ViewProjection);
    output.uv = uvs[vertex_params.vertex_id];
    output.color = sprite.color;

    return output;
}

// [shader("fragment")]
// Fragment main(VertexOut vert) {
//     Fragment output;

//     output.color = float4(vert.color) * tex.Sample(float2(vert.uv));

//     return output;
// }
