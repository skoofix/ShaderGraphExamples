Shader "Hidden/SpeedLinesDistortionURP"
{
    Properties
    {
        _NoiseTex          ("Noise (Repeat)", 2D) = "white" {}
        _LineCount         ("Line Count", Range(0, 2)) = 2.0
        _DistortionPower   ("Distortion Power", Range(0, 0.1)) = 0.034
        _LineFalloff       ("Line Falloff", Range(0, 1)) = 1.0
        _MaskSize          ("Mask Size", Range(0, 1)) = 0.175
        _MaskEdge          ("Mask Edge", Range(0, 1)) = 0.195
        _AnimationSpeed    ("Animation Speed", Range(1, 20)) = 20.0
        _BlurStrength      ("Blur Strength", Range(0, 0.01)) = 0.01
        _EffectPower       ("Effect Power", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        ZWrite Off
        ZTest Always
        Cull Off

        Pass
        {
            Name "SpeedLinesFullScreen"

            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Источник: URP Full Screen Pass передаёт _BlitTexture
            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            CBUFFER_START(UnityPerMaterial)
            float _LineCount;
            float _DistortionPower;
            float _LineFalloff;
            float _MaskSize;
            float _MaskEdge;
            float _AnimationSpeed;
            float _BlurStrength;
            float _EffectPower;
            CBUFFER_END

            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings   { float4 posCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings Vert (Attributes v)
            {
                Varyings o;
                o.posCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                o.uv    = GetFullScreenTriangleTexCoord(v.vertexID);
                return o;
            }

            float inv_lerp(float from, float to, float value)
            {
                return (value - from) / (to - from);
            }

            float2 rotate_uv(float2 uv, float2 pivot, float rotation)
            {
                float c = cos(rotation);
                float s = sin(rotation);
                float2 d = uv - pivot;
                return float2(c*d.x - s*d.y, c*d.y + s*d.x) + pivot;
            }

            float2 polar_coordinates(float2 uv, float2 center, float zoom, float repeatV)
            {
                float2 dir = uv - center;
                float radius = length(dir) * 2.0;
                // Нормализация угла в [0,1)
                float angle = atan2(dir.y, dir.x) * (1.0 / (PI * 2.0));
                return frac(float2(radius * zoom, angle * repeatV));
            }

            float4 Frag (Varyings i) : SV_Target
            {
                float2 uv = i.uv;

                // floor(fract(TIME) * animation_speed)
                float tStep = floor(frac(_Time.y) * _AnimationSpeed);

                // Паттерн линий
                float2 rotUV    = rotate_uv(uv, float2(0.5, 0.5), tStep);
                float2 polarUV  = polar_coordinates(rotUV, float2(0.5, 0.5), 0.01, _LineCount);
                float3 linesTex = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, polarUV).rgb;

                // Радиа́льная маска
                float maskVal        = length(uv - float2(0.5, 0.5));
                float mask           = inv_lerp(_MaskSize, _MaskEdge, maskVal);
                float effectStrength = mask * _DistortionPower * _EffectPower;

                // Интенсивность линий
                float lineIntensity = smoothstep(1.0 - effectStrength, 1.0 - effectStrength + _LineFalloff, linesTex.r);

                // Направление искажения (от центра)
                float2 dir = normalize(uv - float2(0.5, 0.5));
                // защита от NaN в самом центре
                if (!all(isfinite(dir))) dir = float2(1.0, 0.0);

                float2 distortedUV = uv + dir * lineIntensity * effectStrength;

                float4 baseColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, distortedUV);

                // Лёгкое размытие по окружности
                const int kSamples = 8;
                float4 blurColor = 0;
                [unroll] for (int k = 0; k < kSamples; ++k)
                {
                    float a = (k / (float)kSamples) * TWO_PI;
                    float2 offs = float2(cos(a), sin(a)) * _BlurStrength * lineIntensity;
                    blurColor += SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, distortedUV + offs);
                }
                blurColor /= (float)kSamples;

                return lerp(baseColor, blurColor, lineIntensity * 0.5);
            }

            ENDHLSL
        }
    }

    Fallback Off
}
