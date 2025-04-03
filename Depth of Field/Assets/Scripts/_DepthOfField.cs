using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class _DepthOfField : MonoBehaviour
{
    // Pass切换
    // - 计算模糊圈半径CoC
    // - 模糊前图像预处理
    // - 主模糊阶段、产生散景
    // - 对Bokeh结果进行后处理
    // - 将模糊图像与原图组合
    const int circleOfConfusionPass = 0;   
    const int preFilterPass = 1;
    const int bokehPass = 2;
    const int postFilterPass = 3;
    const int combinePass = 4;

    [Range(0.1f, 100f)]
    public float focusDistance = 10f;   // 焦点距离，控制哪个距离图像最清晰
    [Range(0.1f, 10f)]
    public float focusRange = 3f;       // 焦点范围，交点前后多大范围也保持清晰
    [Range(1f, 10f)]
    public float bokehRadius = 4f;      // 散景半径，被模糊的物体要模糊的多厉害
    [HideInInspector]
    public Shader dofShader;
    [NonSerialized]
    Material dofMaterial;

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (dofMaterial == null)
        {
            dofMaterial = new Material(dofShader);
            dofMaterial.hideFlags = HideFlags.HideAndDontSave;
        }

        // 传入参数
        dofMaterial.SetFloat("_BokehRadius", bokehRadius);
        dofMaterial.SetFloat("_FocusDistance", focusDistance);
        dofMaterial.SetFloat("_FocusRange", focusRange);

        // 创建临时RT
        RenderTexture coc = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.RHalf, RenderTextureReadWrite.Linear);

        // 中间纹理
        int width = source.width / 2;
        int height = source.height / 2;
        RenderTextureFormat format = source.format;
        RenderTexture dof0 = RenderTexture.GetTemporary(width, height, 0, format);
        RenderTexture dof1 = RenderTexture.GetTemporary(width, height, 0, format);

        // 传入纹理
        dofMaterial.SetTexture("_CoCTex", coc);
        dofMaterial.SetTexture("_DoFTex", dof0);

        // 渲染
        // - 01 从原图生成CoC
        // - 02 对源图像进行预处理模糊——中间图dof0
        // - 03 主模糊，生成bokeh效果
        // - 04 后处理，优化Bokeh模糊效果
        // - 05 将模糊图像与原图组合
        Graphics.Blit(source, coc, dofMaterial, circleOfConfusionPass);
        // Graphics.Blit(coc, destination); // Debug
        Graphics.Blit(source, dof0, dofMaterial, preFilterPass);
        // Graphics.Blit(dof0, destination); // Debug
        Graphics.Blit(dof0, dof1, dofMaterial, bokehPass);
        // Graphics.Blit(dof1, destination); // Debug
        Graphics.Blit(dof1, dof0, dofMaterial, postFilterPass);
        // Graphics.Blit(dof0, destination); // Debug
        Graphics.Blit(source, destination, dofMaterial, combinePass);

        // 释放资源
        RenderTexture.ReleaseTemporary(coc);
        RenderTexture.ReleaseTemporary(dof0);
        RenderTexture.ReleaseTemporary(dof1);
    }






}
