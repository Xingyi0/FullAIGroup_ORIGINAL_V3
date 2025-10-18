FROM runpod/worker-comfyui:5.2.0-base

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
ENV COMBERT_DIR=/workspace/ComfyUI
WORKDIR $COMBERT_DIR

# ---- 基础依赖：加入 gawk 修复 awk 不存在的问题 ----
RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git git-lfs wget unzip ca-certificates \
        libgl1 libglib2.0-0 ffmpeg \
        gawk && \
    git lfs install && \
    update-ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- 自定义节点 ----
WORKDIR $COMBERT_DIR/custom_nodes
RUN set -eux && \
    git clone https://github.com/evanspearman/ComfyMath.git && \
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

# ---- 合并并安装依赖（过滤冲突大件；加入更清晰的日志）----
WORKDIR $COMBERT_DIR
RUN set -eux; \
    (find custom_nodes -name "requirements.txt" -exec cat {} + || true) > /tmp/requirements_all.txt; \
    # 若为空，直接跳过
    if [ ! -s /tmp/requirements_all.txt ]; then \
        echo "No requirements.txt found in custom_nodes. Skipping pip install."; \
    else \
        echo "Raw combined requirements:"; head -n 50 /tmp/requirements_all.txt || true; \
        # 过滤 torch/onnxruntime/xformers/triton/nvidia*/tensorrt 等大件，避免与基础镜像冲突
        gawk 'BEGIN{IGNORECASE=1} \
            !/^torch([[:space:]=<>+.-].*)?$/ && \
            $0 !~ /^torchvision/ && \
            $0 !~ /^torchaudio/ && \
            $0 !~ /^xformers/ && \
            $0 !~ /^onnxruntime/ && \
            $0 !~ /^triton/ && \
            $0 !~ /^tensorrt/ && \
            $0 !~ /^nvidia-/ {print}' \
            /tmp/requirements_all.txt > /tmp/requirements_runtime.txt; \
        echo "Filtered runtime requirements (first 100 lines):"; head -n 100 /tmp/requirements_runtime.txt || true; \
        if [ -s /tmp/requirements_runtime.txt ]; then \
            pip install --no-cache-dir -r /tmp/requirements_runtime.txt || { \
                echo "pip install failed. Showing filtered requirements to help debug:"; \
                cat /tmp/requirements_runtime.txt; \
                exit 1; \
            }; \
        else \
            echo "Filtered requirements list is empty. Skipping pip install."; \
        fi; \
    fi; \
    rm -f /tmp/requirements_all.txt /tmp/requirements_runtime.txt

# ---- 模型目录 ----
RUN mkdir -p models/checkpoints models/vae models/controlnet models/sams models/ultralytics/bbox \
    models/insightface/models models/insightface models/reswapper models/hyperswap \
    models/facerestore_models models/upscale_models

# ---- 下载模型（带重试/超时）----
ARG WGET_OPTS="--tries=3 --timeout=30 -c"
RUN set -eux && \
    wget $WGET_OPTS https://huggingface.co/SG161222/RealVisXL_V5.0_Lightning/resolve/main/RealVisXL_V5.0_Lightning_fp16.safetensors -P models/checkpoints/ && \
    wget $WGET_OPTS https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors -P models/vae/ && \
    wget $WGET_OPTS https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors -P models/controlnet/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth -P models/sams/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/detection/bbox/face_yolov8m.pt -P models/ultralytics/bbox/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/buffalo_l.zip -P models/insightface/models/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx -P models/insightface/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/reswapper_128.onnx -P models/reswapper/ && \
    wget $WGET_OPTS https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1a_256.onnx -P models/hyperswap/ && \
    wget $WGET_OPTS https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1b_256.onnx -P models/hyperswap/ && \
    wget $WGET_OPTS https://huggingface.co/facefusion/models-3.3.0/resolve/main/hyperswap_1c_256.onnx -P models/hyperswap/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth -P models/facerestore_models/ && \
    wget $WGET_OPTS https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GPEN-BFR-512.onnx -P models/facerestore_models/ && \
    wget $WGET_OPTS https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x2.pth -P models/upscale_models/

# ---- 解压 InsightFace ----
WORKDIR $COMBERT_DIR/models/insightface/models/
RUN unzip -o buffalo_l.zip -d buffalo_l && rm -f buffalo_l.zip

# ---- 路径重映射配置 ----
WORKDIR $COMBERT_DIR
RUN mkdir -p templates && \
    mkdir -p custom_nodes/ComfyUI-Custom-Scripts/user && \
    printf '{\n  "input": "$input/**/*.txt",\n  "output": "$output/**/*.txt",\n  "temp": "$temp/**/*.txt",\n  "templates": "/workspace/ComfyUI/templates/**/*.txt"\n}\n' \
      > custom_nodes/ComfyUI-Custom-Scripts/user/text_file_dirs.json

WORKDIR /
