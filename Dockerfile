# 阶段 I: 使用 RunPod 官方的 ComfyUI Worker 基础镜像
# 这是一个干净的 ComfyUI 安装，包含运行 Serverless API 所需的 RunPod Worker Handler
# FROM runpod/worker-comfyui:latest-base
# 修正后的第一行 (使用已知的稳定版本，例如 5.2.0-base):
FROM runpod/worker-comfyui:5.2.0-base

# 设置默认 Shell 和工作目录
SHELL ["/bin/bash", "-c"]
ENV COMBERT_DIR=/workspace/ComfyUI
WORKDIR $COMBERT_DIR

# 安装核心系统依赖：Git用于克隆，wget用于下载大文件，unzip用于解压
RUN apt-get update && \
    apt-get install -y git wget unzip python3-zipfile && \
    apt-get clean

# --------------------------------------------------------------------------------
# 阶段 II: 安装所有自定义节点并汇总 Python 依赖
# --------------------------------------------------------------------------------
WORKDIR $COMBERT_DIR/custom_nodes

# 1. 批量克隆所有自定义节点仓库
RUN git clone https://github.com/evanspearman/ComfyMath.git
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
RUN git clone https://github.com/chflame163/ComfyUI_LayerStyle.git
# 注意: Subpack 必须单独克隆才能获取 UltralyticsDetectorProvider 节点
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git
RUN git clone https://github.com/Gourieff/ComfyUI-ReActor.git
RUN git clone https://github.com/Acly/comfyui-tooling-nodes.git
RUN git clone https://github.com/twri/sdxl_prompt_styler.git
RUN git clone https://github.com/WainWong/ComfyUI-Loop-image.git
RUN git clone https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git
RUN git clone https://github.com/1038lab/ComfyUI-RMBG.git
RUN git clone https://github.com/rgthree/rgthree-comfy.git
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git
RUN git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git
# ComfyUI-Custom-Scripts 必须安装，因为它涉及路径重映射配置

# 2. 汇总并安装所有自定义节点的 Python 依赖
# 这是一个专业步骤，用于避免各个节点之间可能存在的依赖版本冲突 (如 torch, onnxruntime)
WORKDIR $COMBERT_DIR
RUN echo "Collecting all requirements into one master file..." && \
    find custom_nodes -name "requirements.txt" -exec cat {} + >> requirements_master.txt && \
    pip install -r requirements_master.txt --upgrade --ignore-installed && \
    rm requirements_master.txt

# --------------------------------------------------------------------------------
# 阶段 III: 模型下载和文件处理
# --------------------------------------------------------------------------------

# 创建所有必需的模型子目录
RUN mkdir -p models/checkpoints models/vae models/controlnet models/sams models/ultralytics/bbox \
    models/insightface/models models/insightface models/reswapper models/hyperswap \
    models/facerestore_models models/upscale_models

# 定义下载函数 (使用 wget -c 确保下载的鲁棒性)
# H/F URL: RealVisXL Checkpoint
RUN wget -c https://huggingface.co/SG161222/RealVisXL_V5.0_Lightning/resolve/main/RealVisXL_V5.0_Lightning_fp16.safetensors -P models/checkpoints/

# H/F URL: SDXL VAE
RUN wget -c https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors -P models/vae/

# H/F URL: ControlNet
RUN wget -c https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors -P models/controlnet/

# H/F URL: Face Segment (SAM)
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth -P models/sams/

# H/F URL: YOLOv8 Face Bbox Detector
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt -P models/ultralytics/bbox/

# H/F URL: InsightFace Model (buffalo_l.zip)
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/buffalo_l.zip -P models/insightface/models/

# H/F URL: Face Swapper ONNX
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx -P models/insightface/

# H/F URL: Reswapper
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/reswapper_128.onnx -P models/reswapper/

# H/F URL: Hyperswap Models
RUN wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1a_256.onnx -P models/hyperswap/
RUN wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1b_256.onnx -P models/hyperswap/
RUN wget -c https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1c_256.onnx -P models/hyperswap/

# H/F URL: Face Restoration Models
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth -P models/facerestore_models/
RUN wget -c https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GPEN-BFR-512.onnx -P models/facerestore_models/

# H/F URL: Upscale Model
RUN wget -c https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x2.pth -P models/upscale_models/

# **处理特殊指令：InsightFace 模型解压**
# 根据用户提供的指令，将 buffalo_l.zip 解压到 models/insightface/models/buffalo_l/ 目录
WORKDIR $COMBERT_DIR/models/insightface/models/
RUN python3 -m zipfile -e buffalo_l.zip buffalo_l && \
    rm buffalo_l.zip

# --------------------------------------------------------------------------------
# 阶段 IV: 配置路径重映射 (ComfyUI-Custom-Scripts)
# --------------------------------------------------------------------------------

WORKDIR $COMBERT_DIR
# 1. 创建模板文件存储的目录
RUN mkdir -p templates

# 2. 创建并注入适配 Linux 路径的 text_file_dirs.json 配置
# 原始 Windows 路径: "C:/ai/api_server/templates/**/*.txt"
# 适配 Linux 路径: "/workspace/ComfyUI/templates/**/*.txt"
RUN echo '{\n\
    "input": "$input/**/*.txt",\n\
    "output": "$output/**/*.txt",\n\
    "temp": "$temp/**/*.txt",\n\
    "templates": "/workspace/ComfyUI/templates/**/*.txt"\n\
}' > custom_nodes/ComfyUI-Custom-Scripts/user/text_file_dirs.json

# 最终工作目录重置为 Worker 期望的根目录
WORKDIR /