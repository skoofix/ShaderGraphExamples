Shader "Volumetrics/UnderwaterWavesURP"
{
    Properties
    {
        _TimeSpeed        ("time_speed", Range(0,3)) = 1.0
        [Toggle] _FlipY   ("flip_y", Float) = 0

        _SeaDark          ("sea_color_dark",  Color) = (0.04,0.32,0.55,1)
        _SeaLight         ("sea_color_light", Color) = (0.06,0.47,0.60,1)
        _RefractColor     ("refraction_color", Color) = (0.96,0.98,0.86,1)
        _ShaftColor       ("light_shaft_color", Color) = (0.88,0.90,0.78,1)
    }

    SubShader
    {
        Tags{ "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "RenderType"="Transparent" }
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Back

        Pass
        {
            Name "ForwardUnlit"
            Tags{ "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings {
                float4 positionHCS : SV_POSITION;
                float4 screenPos   : TEXCOORD1;   // для координат экрана
                float2 uv          : TEXCOORD0;   // пригодится для виньетки
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            CBUFFER_START(UnityPerMaterial)
                float _TimeSpeed;
                float _FlipY;

                float4 _SeaDark;
                float4 _SeaLight;
                float4 _RefractColor;
                float4 _ShaftColor;
            CBUFFER_END

            Varyings vert (Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.positionHCS = TransformObjectToHClip(v.positionOS.xyz);
                o.screenPos   = ComputeScreenPos(o.positionHCS);
                o.uv          = v.uv;
                return o;
            }

            // ---------- helpers (порт 1:1 из Godot) ----------
            float hash(float2 p)
            {
                return 0.5 * (sin(dot(p, float2(271.319, 413.975)) + 1217.13 * p.x * p.y)) + 0.5;
            }

            float noise(float2 p)
            {
                float2 w = frac(p);
                w = w * w * (3.0 - 2.0 * w);
                p = floor(p);
                return lerp( lerp(hash(p + float2(0,0)), hash(p + float2(1,0)), w.x),
                             lerp(hash(p + float2(0,1)), hash(p + float2(1,1)), w.x), w.y);
            }

            float map_octave(float2 uv)
            {
                uv = (uv + noise(uv)) / 2.5;
                uv = float2(uv.x * 0.6 - uv.y * 0.8, uv.x * 0.8 + uv.y * 0.6);
                float2 uvsin = 1.0 - abs(sin(uv));
                float2 uvcos = abs(cos(uv));
                uv = lerp(uvsin, uvcos, uvsin);
                float val = 1.0 - pow(uv.x * uv.y, 0.65);
                return val;
            }

            float mapSDF(float3 p, float timeSpeed)
            {
                float2 uv = p.xz + (_Time.y * timeSpeed) / 2.0;
                float amp = 0.6, freq = 2.0, val = 0.0;

                [unroll] for(int i = 0; i < 3; ++i) {
                    val += map_octave(uv) * amp;
                    amp *= 0.3;
                    uv *= freq;
                }

                uv = p.xz - 1000.0 - (_Time.y * timeSpeed) / 2.0;
                amp = 0.6; freq = 2.0;

                [unroll] for(int i = 0; i < 3; ++i) {
                    val += map_octave(uv) * amp;
                    amp *= 0.3;
                    uv *= freq;
                }
                return val + 3.0 - p.y;
            }

            float3 getNormal(float3 p, float eps, float timeSpeed)
            {
                float3 px = p + float3(eps, 0.0, 0.0);
                float3 pz = p + float3(0.0, 0.0, eps);
                // как в оригинале Godot:
                return normalize(float3(mapSDF(px, timeSpeed), eps, mapSDF(pz, timeSpeed)));
            }

            struct RaymarchResult { float3 hit_pos; float hit_t; float dist; };

            RaymarchResult raymarch(float3 ro, float3 rd, float eps, float timeSpeed)
            {
                RaymarchResult result;
                float l = 0.0, r = 26.0;
                int steps = 16;
                float dist = 1e6;

                [loop] for(int i = 0; i < steps; ++i)
                {
                    float mid = (r + l) * 0.5;
                    float mapmid = mapSDF(ro + rd * mid, timeSpeed);
                    dist = min(dist, abs(mapmid));
                    if (mapmid > 0.0) l = mid; else r = mid;
                    if (r - l < eps) break;
                }
                result.hit_pos = ro + rd * l;
                result.hit_t = l;
                result.dist = dist;
                return result;
            }

            float fbm(float2 n)
            {
                float total = 0.0, amplitude = 1.0;
                [unroll] for (int i = 0; i < 5; i++) {
                    total += noise(n) * amplitude;
                    n += n;
                    amplitude *= 0.4;
                }
                return total;
            }

            float lightShafts(float2 st, float timeSpeed)
            {
                float angle = -0.2;
                float2 _st = st;
                float t = (_Time.y * timeSpeed) / 16.0;
                float s = sin(angle), c = cos(angle);
                st = float2(st.x * c - st.y * s, st.x * s + st.y * c);

                float val = fbm(float2(st.x * 2.0 + 200.0 + t, st.y / 4.0));
                val += fbm(float2(st.x * 2.0 + 200.0 - t, st.y / 4.0));
                val = val / 3.0;

                float mask = pow(saturate(1.0 - abs(_st.y - 0.15)) * 0.49 + 0.5, 2.0);
                mask *= (saturate(1.0 - abs(_st.x + 0.2)) * 0.49 + 0.5);
                return pow(val * mask, 2.0);
            }

            float2 bubble(float2 uv, float scale, float timeSpeed)
            {
                if (uv.y > 0.2) return float2(0.0, 0.0);
                float t = (_Time.y * timeSpeed) / 4.0;
                float2 st = uv * scale;
                float2 _st = floor(st);
                float2 bias = float2(0.0, 4.0 * sin(_st.x * 128.0 + t));
                float mask = smoothstep(0.1, 0.2, -cos(_st.x * 128.0 + t));
                st += bias;
                float2 _st_ = floor(st);
                st = frac(st);
                float size = noise(_st_) * 0.07 + 0.01;
                float2 pos = float2(noise(float2(t, _st_.y * 64.1)) * 0.8 + 0.1, 0.5);
                if (length(st - pos) < size)
                {
                    return (st + pos) * float2(0.1, 0.2) * mask;
                }
                return float2(0.0, 0.0);
            }

            half4 frag (Varyings i) : SV_Target
            {
                // --- эквиваленты FRAGCOORD/SCREEN_PIXEL_SIZE ---
                float2 res = _ScreenParams.xy;                         // (width, height)
                float2 uv01 = (i.screenPos.xy / i.screenPos.w);        // 0..1
                float2 uv = float2( (uv01.x * 2.0 - 1.0) * (res.x / res.y),
                                    (uv01.y * 2.0 - 1.0) );
                if (_FlipY > 0.5) uv.y *= -1.0;

                float eps = 1.0 / res.x;

                uv.y *= 0.5;
                uv.x *= 0.45;
                uv += bubble(uv, 12.0, _TimeSpeed) + bubble(uv, 24.0, _TimeSpeed);

                float3 ro = float3(0.0, 0.0, 2.0);
                float3 rd = normalize(float3(uv, -1.0));

                RaymarchResult result = raymarch(ro, rd, eps, _TimeSpeed);

                float3 normal = getNormal(result.hit_pos, eps, _TimeSpeed);
                float diffuse = dot(normal, rd) * 0.5 + 0.5;

                float3 color = lerp(_SeaDark.rgb, _SeaLight.rgb, diffuse);
                color += pow(diffuse, 12.0);

                float3 lightPos = float3(8.0, 3.0, -3.0);
                float3 refVec = normalize(refract(result.hit_pos - lightPos, normal, 0.05));
                float refraction = saturate(dot(refVec, rd));
                color += _RefractColor.rgb * 0.6 * pow(refraction, 1.5);

                float3 col = lerp(color, _SeaDark.rgb, pow(saturate(result.dist), 0.2));
                col += _ShaftColor.rgb * lightShafts(uv, _TimeSpeed);
                col = (col * col + sin(col)) / float3(1.8, 1.8, 1.9);

                // лёгкая виньетка (как в Godot: q = UV)
                float2 q = i.uv; // 0..1
                col *= 0.7 + 0.3 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.2);

                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
