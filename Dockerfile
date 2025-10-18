# 阶段 I: 使用 RunPod 官方的 ComfyUI Worker 基础镜像（固定到已知稳定版本）
FROM runpod/worker-comfyui:5.2.0-base

# 基础环境
SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV COMBERT_DIR=/workspace/ComfyUI
WORKDIR $COMBERT_DIR

# 核心系统依赖
# 说明：
# - 移除不存在的 python3-zipfile（zipfile 是 Python 标准库模块，无需安装）
# - 加入 ca-certificates，避免 HTTPS 证书问题
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        wget \
        unzip \
        ca-certificates && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------------------
# 阶段 II: 安装所有自定义节点并汇总 Python 依赖
# --------------------------------------------------------------------------------
WORKDIR $COMBERT_DIR/custom_nodes

# 批量克隆自定义节点
RUN git clone https://github.com/evanspearman/ComfyMath.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    git clone https://github.com/chflame163/ComfyUI_LayerStyle.git && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git && \
    git clone https://github.com/Gourieff/ComfyUI-ReActor.git && \
    git clone https://github.com/Acly/comfyui-tooling-nodes.git && \
    git clone https://github.com/twri/sdxl_prompt_styler.git && \
    git clone https://github.com/WainWong/ComfyUI-Loop-image.git && \
    git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git && \
    git clone https://github.com/1038lab/ComfyUI-RMBG.git && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git

# 汇总并安装 Python 依赖
WORKDIR $COMBERT_DIR
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
RUN echo "Collecting all requirements into one master file..." && \
    find custom_nodes -name "requirements.txt" -exec cat {} + >> requirements_master.txt || true && \
    # 有些节点可能没有 requirements.txt，上面用 || true 避免构建中断
    if [ -s requirements_master.txt ]; then pip install -r requirements_master.txt --upgrade --no-cache-dir; fi && \
    rm -f requirements_master.txt

# --------------------------------------------------------------------------------
# 阶段 III: 模型下载和文件处理
# --------------------------------------------------------------------------------

# 创建目录
RUN mkdir -p models/checkpoints models/vae models/controlnet models/sams models/ultralytics/bbox \
    models/insightface/models models/insightface models/reswapper models/hyperswap \
    models/facerestore_models models/upscale_models

# 下载模型（使用 wget -c 具备断点续传，避免偶发失败）
RUN wget -c https://huggingface.co/SG161222/RealVisXL_V5.0_Lightning/resolve/main/RealVisXL_V5.0_Lightning_fp16.safetensors -P models/checkpoints/ && \
    wget -c https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors -P models/vae/ && \
    wget -c https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors -P models/controlnet/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth -P models/sams/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt -P models/ultralytics/bbox/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/buffalo_l.zip -P models/insightface/models/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx -P models/insightface/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/reswapper_128.onnx -P models/reswapper/ && \
    wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1a_256.onnx -P models/hyperswap/ && \
    wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1b_256.onnx -P models/hyperswap/ && \
    wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1c_256.onnx -P models/hyperswap/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth -P models/facerestore_models/ && \
    wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GPEN-BFR-512.onnx -P models/facerestore_models/ && \
    wget -c https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x2.pth -P models/upscale_models/

# 解压 InsightFace buffalo_l.zip -> models/insightface/models/buffalo_l/
WORKDIR $COMBERT_DIR/models/insightface/models/
RUN unzip -o buffalo_l.zip -d buffalo_l && rm -f buffalo_l.zip

# --------------------------------------------------------------------------------
# 阶段 IV: 配置路径重映射 (ComfyUI-Custom-Scripts)
# --------------------------------------------------------------------------------
WORKDIR $COMBERT_DIR
RUN mkdir -p templates && \
    mkdir -p custom_nodes/ComfyUI-Custom-Scripts/user && \
    echo '{\n\
    "input": "$input/**/*.txt",\n\
    "output": "$output/**/*.txt",\n\
    "temp": "$temp/**/*.txt",\n\
    "templates": "/workspace/ComfyUI/templates/**/*.txt"\n\
}' > custom_nodes/ComfyUI-Custom-Scripts/user/text_file_dirs.json

# 最终工作目录重置为 Worker 期望的根目录
WORKDIR /
