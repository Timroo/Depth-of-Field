Shader "_DepthOfField"{
    Properties{
        _MainTex("Texture", 2D) = "white" {}
    }

    CGINCLUDE
        #include "UnityCG.cginc"
        sampler2D _MainTex;
        sampler2D _CameraDepthTexture;
        sampler2D _CoCTex;
        sampler2D _DoFTex;

        float4 _MainTex_TexelSize;

        float _BokehRadius;
        float _FocusDistance;
        float _FocusRange;

        struct a2v{
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };
        struct v2f{
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
        };

        v2f vert(a2v v){
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.uv;
            return o;
        }
    ENDCG

    SubShader{
        Cull Off ZTest Always ZWrite Off

        // 0 circleOfConfusionPass
        Pass{
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag

                half frag(v2f i):SV_Target{
                    float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                    // 相机空间下的线性深度
                    depth = LinearEyeDepth(depth);

                    // coc公式：当前像素距离焦点有多远，越远就越模糊。
                    float coc = (depth - _FocusDistance) / _FocusRange;
                    // 将模糊强度限制在[-1,1],根据散景半径放大CoC，控制最终模糊圈大小
                    coc = clamp(coc, -1, 1) * _BokehRadius;
                    // if(coc < 0) coc = -coc; // 方便查看对焦区域
                    return coc;
                }
            ENDCG
        }

        // 1 preFilterPass
        Pass{
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag

                // 根据颜色亮度计算一个权重值，暗色更重，亮色更轻：
                // - 越暗max越小，权重越大
                half Weigh(half3 c){
                    return 1 / ( 1 + max(max(c.r, c.g), c.b));
                }

                half4 frag(v2f i): SV_Target{
                    // 4个方向的偏移：o = (-0.5,-0.5,0.5,0.5)
                    float4 o = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
                    // 对周围4个像素采样并计算权重
                    half3 s0 = tex2D(_MainTex, i.uv + o.xy).rgb; // 左上 -0.5,-0.5
                    half3 s1 = tex2D(_MainTex, i.uv + o.zy).rgb; // 右上 0.5,-0.5
                    half3 s2 = tex2D(_MainTex, i.uv + o.xw).rgb; // 左下 -0.5,0.5
                    half3 s3 = tex2D(_MainTex, i.uv + o.zw).rgb; // 右下 0.5,0.5
                    half w0 = Weigh(s0);
                    half w1 = Weigh(s1);
                    half w2 = Weigh(s2);
                    half w3 = Weigh(s3);
                    // 用权重进行模糊
                    half3 color = s0 * w0 + s1 * w1 + s2 * w2 + s3 * w3;
                    color /= max(w0 + w1 + w2 + w3, 0.00001);
                    // 采样CoC值
                    half coc0 = tex2D(_CoCTex, i.uv + o.xy).r;
                    half coc1 = tex2D(_CoCTex, i.uv + o.zy).r;
                    half coc2 = tex2D(_CoCTex, i.uv + o.xw).r;
                    half coc3 = tex2D(_CoCTex, i.uv + o.zw).r;
                    // 合并CoC值
                    half cocMin = min(min(min(coc0, coc1), coc2), coc3);
                    half cocMax = max(max(max(coc0, coc1), coc2), coc3);
                    // CoC 有正负方向（背景模糊是正，前景模糊是负）。
                    // 选择“模糊程度更强的方向”作为当前像素的模糊值。
                    half coc = cocMax >= -cocMin ? cocMax : cocMin;
                    // coc = tex2D(_CoCTex, i.uv).r;
                    return half4(color, coc);
                }

                half4 frag1(v2f i): SV_Target{
                    half3 color = tex2D(_MainTex, i.uv).rgb;
                    half coc = tex2D(_CoCTex, i.uv).r;
                    return half4(color, coc);
                }

            ENDCG
        }

        // 2 bokehPass
        Pass{
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag

                #define BOKEH_KERNEL_MEDIUM
                // Bokeh 核（kernel）：模拟一个“光圈”形状

				// From https://github.com/Unity-Technologies/PostProcessing/
				// blob/v2/PostProcessing/Shaders/Builtins/DiskKernels.hlsl
                // 低密度16个点
				#if defined(BOKEH_KERNEL_SMALL)
					static const int kernelSampleCount = 16;
					static const float2 kernel[kernelSampleCount] = {
						float2(0, 0),
						float2(0.54545456, 0),
						float2(0.16855472, 0.5187581),
						float2(-0.44128203, 0.3206101),
						float2(-0.44128197, -0.3206102),
						float2(0.1685548, -0.5187581),
						float2(1, 0),
						float2(0.809017, 0.58778524),
						float2(0.30901697, 0.95105654),
						float2(-0.30901703, 0.9510565),
						float2(-0.80901706, 0.5877852),
						float2(-1, 0),
						float2(-0.80901694, -0.58778536),
						float2(-0.30901664, -0.9510566),
						float2(0.30901712, -0.9510565),
						float2(0.80901694, -0.5877853),
					};
                // 中密度22个点
				#elif defined (BOKEH_KERNEL_MEDIUM)
					static const int kernelSampleCount = 22;
					static const float2 kernel[kernelSampleCount] = {
						float2(0, 0),
						float2(0.53333336, 0),
						float2(0.3325279, 0.4169768),
						float2(-0.11867785, 0.5199616),
						float2(-0.48051673, 0.2314047),
						float2(-0.48051673, -0.23140468),
						float2(-0.11867763, -0.51996166),
						float2(0.33252785, -0.4169769),
						float2(1, 0),
						float2(0.90096885, 0.43388376),
						float2(0.6234898, 0.7818315),
						float2(0.22252098, 0.9749279),
						float2(-0.22252095, 0.9749279),
						float2(-0.62349, 0.7818314),
						float2(-0.90096885, 0.43388382),
						float2(-1, 0),
						float2(-0.90096885, -0.43388376),
						float2(-0.6234896, -0.7818316),
						float2(-0.22252055, -0.974928),
						float2(0.2225215, -0.9749278),
						float2(0.6234897, -0.7818316),
						float2(0.90096885, -0.43388376),
					};
				#endif
                
                half Weigh (half coc, half radius){
                    // radius 当前采样点相对于中心点的距离
                    // coc 当前像素的模糊值
                    // 判断一个像素的 CoC 值（即模糊程度）是否足够大，应该对当前像素产生影响
                    return saturate((coc - radius + 2) / 2);
                }

                half4 frag(v2f i): SV_Target{
                    half coc = tex2D(_MainTex, i.uv).a;

                    half3 bgColor = 0;
                    half3 fgColor = 0;
                    half bgWeight = 0;
                    half fgWeight = 0;

                    // 开始环形核采样
                    for (int k = 0; k < kernelSampleCount; k++){
                        // o = 样本偏移 * 散景半径 : 控制 Bokeh 圆圈大小
                        float2 o = kernel[k] * _BokehRadius;
                        half radius = length(o);
                        o *= _MainTex_TexelSize.xy;
                        half4 s = tex2D(_MainTex, i.uv + o);

                        // 背景采样
                        half bgW = Weigh(max(0, min(s.a, coc)), radius);
                        bgColor += s.rgb * bgW;
                        bgWeight += bgW;

                        // 前景采样
                        half fgw = Weigh(-s.a, radius);
                        fgColor += s.rgb * fgw;
                        fgWeight += fgw;
                    }
                    // 最终混合
                    bgColor *= 1 / (bgWeight + (bgWeight == 0));
                    fgColor *= 1 / (fgWeight + (fgWeight == 0));
                    // 前景遮挡比例
                    // half bgfg = min(1, fgWeight * 2 * 3.14159265359 / kernelSampleCount);
                    half bgfg = min(1, fgWeight * 3.14159265359 / kernelSampleCount);
                    // half bgfg = min(1, fgWeight / kernelSampleCount);
                    // 根据前景遮挡权重混合颜色
                    half3 color = lerp(bgColor, fgColor, bgfg);
                    return half4(color, bgfg);
                }

                // 仅模糊
                half4 frag1(v2f i): SV_Target{
                    half3 color = 0;
					for (int k = 0; k < kernelSampleCount; k++) {
						float2 o = kernel[k];
						o *= _MainTex_TexelSize.xy * _BokehRadius;
						color += tex2D(_MainTex, i.uv + o).rgb;
					}
					color *= 1.0 / kernelSampleCount;
					return half4(color, 1);
                }

                // 根据CoC进行模糊
                half4 frag2(v2f i): SV_Target{
                    half3 color = 0;
                    half weight = 0;
                    for (int k = 0; k < kernelSampleCount; k++) {
                            float2 o = kernel[k] * _BokehRadius;
                            half radius = length(o);
                            o *= _MainTex_TexelSize.xy;
                            half coc = tex2D(_CoCTex, i.uv + o).r * radius;
                            if(abs(coc) >= radius)
                            {
                                color += tex2D(_MainTex, i.uv + o).rgb;
                                weight += 1;
                            }
                        }
                        color *= 1.0 / weight;
                        return half4(color, 1);
                }
                
            ENDCG
        }

        // 3 postFilterPass
        Pass{
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                // 对上一个 Bokeh Pass 的结果进行一次简单平滑模糊（均值模糊）
                // - 去掉锯齿、块状感，让散景更自然柔和
                half4 frag(v2f i): SV_Target{
                    float4 o = _MainTex_TexelSize.xyxy * float2(-0.5, 0.5).xxyy;
                    half4 s =   tex2D(_MainTex, i.uv + o.xy) +
                                tex2D(_MainTex, i.uv + o.zy) +
                                tex2D(_MainTex, i.uv + o.xw) +
                                tex2D(_MainTex, i.uv + o.zw);
                    return s * 0.25;
                }
            ENDCG
        }
        
        // 4 combinePass
        Pass { 
            CGPROGRAM
                #pragma vertex vert
                #pragma fragment frag
                half4 frag(v2f i): SV_Target{
                    half4 source = tex2D(_MainTex, i.uv);
                    half coc = tex2D(_CoCTex, i.uv).r;  // 该像素的模糊程度
                    half4 dof = tex2D(_DoFTex, i.uv);   // 模糊图像的像素颜色和遮挡信息

                    // 将 CoC 映射到 [0,1] 的模糊强度
                    half dofStrength = smoothstep(0.1, 1, abs(coc));
                    // 类似于 alpha 合成逻辑
                    // - 效果：当前像素如果被前景遮挡，就使用前景模糊结果；否则使用背景模糊 + 原图的混合
                    half3 color = lerp(source.rgb, dof.rgb, 
                                        1 - (1 - dofStrength) * (1 - dof.a));
                                    
                    return half4(color, source.a);
                }
            ENDCG
        }
    }
}
