Shader "Universal Render Pipeline/Unlit/Melt2D_URP_Directional"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _Progress ("Progress", Range(0,1)) = 0
        _Meltiness ("Meltiness", Range(0,16)) = 1
        _AlphaClip ("Alpha Clip Threshold (0=off)", Range(0,1)) = 0
        [Toggle]_InvertDir ("Invert Direction", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float4 _Color;
                float _Progress;
                float _Meltiness;
                float _AlphaClip;
                float _InvertDir;
            CBUFFER_END

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.color = IN.color;
                return OUT;
            }

            float pseudo_rand(float x)
            {
                return fmod(x * 2048103.0 + cos(x * 1912.0), 1.0);
            }

            float4 frag (Varyings IN) : SV_Target
            {
                float2 uv = IN.uv;
                float4 col;

                float snappedX = uv.x - fmod(uv.x, _MainTex_TexelSize.x);
                bool inv = (_InvertDir > 0.5);

                if (!inv)
                {
                    float safeY = max(uv.y, 1e-4);
                    uv.y -= _Progress / safeY;
                    uv.y -= _Progress * _Meltiness * pseudo_rand(snappedX);
                    col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * IN.color * _Color;
                    if (uv.y <= 0.0) col.a = 0.0;
                }
                else
                {
                    float safeFromBottom = max(1.0 - uv.y, 1e-4);
                    uv.y += _Progress / safeFromBottom;
                    uv.y += _Progress * _Meltiness * pseudo_rand(snappedX);
                    col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv) * IN.color * _Color;
                    if (uv.y >= 1.0) col.a = 0.0;
                }

                if (_AlphaClip > 0.0) clip(col.a - _AlphaClip);
                return col;
            }
            ENDHLSL
        }
    }
}
