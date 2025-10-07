Shader "Custom/ItemHighlighter_Unlit"
{
    Properties
    {
        _ShineColor   ("Shine Color", Color) = (1,1,1,1)
        _ShineSpeed   ("Shine Speed", Range(0,25)) = 1.0
        _ShineWidth   ("Shine Width", Range(0,2))  = 1.0
        _CycleInterval("Cycle Interval", Range(0,100)) = 1.0
        _AngleFade    ("Angle Fade", Range(0,1)) = 1.0
        _Direction    ("Highlight Direction (xyz)", Vector) = (0,0,1,0)

        _ProjLength   ("Projection Length (units along dir)", Float) = 1.0
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" }
        LOD 100

        Cull Back
        ZWrite Off
        ZTest LEqual
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"

            float4 _ShineColor;
            float  _ShineSpeed;
            float  _ShineWidth;
            float  _CycleInterval;
            float  _AngleFade;
            float4 _Direction;
            float  _ProjLength;

            struct appdata {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f {
                float4 pos      : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNrm : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert (appdata v){
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float4 wpos = mul(unity_ObjectToWorld, v.vertex);
                o.worldPos = wpos.xyz;
                o.worldNrm = UnityObjectToWorldNormal(v.normal);
                o.pos = UnityObjectToClipPos(v.vertex);
                return o;
            }

            float sawtooth(float x, float speed, float width, float interval, float timeSec){
                float denom = (width + interval);
                float y = (x + speed * timeSec) / denom;
                return 2.0 * (y - floor(0.5 + y));
            }

            fixed4 frag (v2f i) : SV_Target {
                float3 dir = normalize(_Direction.xyz);

                // нормализация по длине объекта вдоль направления
                float proj = dot(i.worldPos, dir) / max(_ProjLength, 1e-5);

                float t = _Time.y;
                float s0 = sawtooth(proj, _ShineSpeed, _ShineWidth, _CycleInterval, t);
                float s1 = sawtooth(proj + _ShineWidth, _ShineSpeed, _ShineWidth, _CycleInterval, t);
                float frequency = ceil(s0 - s1);

                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);
                float ndotv = dot(normalize(i.worldNrm), viewDir);
                float alpha = saturate((1.0 - ndotv * _AngleFade) * frequency * _ShineColor.a);

                return float4(_ShineColor.rgb, alpha);
            }
            ENDCG
        }
    }
    FallBack Off
}
