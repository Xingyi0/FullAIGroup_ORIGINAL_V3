FROM runpod/worker-comfyui:5.2.0-base

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_CACHE_DIR=1
ENV COMBERT_DIR=/workspace/ComfyUI

WORKDIR $COMBERT_DIR

# ---- 基础与运行时依赖 + 构建工具链 ----
RUN set -eux && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git git-lfs wget unzip ca-certificates \
        libgl1 libglib2.0-0 ffmpeg \
        build-essential python3-dev pkg-config cmake cython3 \
        libffi-dev libssl-dev zlib1g-dev \
        libjpeg-dev libpng-dev libturbojpeg0 \
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

# ---- 合并/清洗/过滤 requirements 并安装 ----
WORKDIR $COMBERT_DIR
RUN set -eux; \
    (find custom_nodes -name "requirements.txt" -exec cat {} + || true) > /tmp/requirements_all.txt; \
    if [ ! -s /tmp/requirements_all.txt ]; then \
        echo "No requirements.txt found in custom_nodes. Skipping pip install."; \
    else \
        echo "Raw combined requirements (first 80 lines):"; head -n 80 /tmp/requirements_all.txt || true; \
        # 清洗：去掉 \r、去掉 # 后注释（无论前面是否有空格）、trim 空白、去空行
        gawk '{ gsub(/\r/, ""); sub(/#.*/, ""); $1=$1; if (length($0)>0) print }' \
            /tmp/requirements_all.txt > /tmp/requirements_clean.txt; \
        echo "Cleaned requirements (first 80 lines):"; head -n 80 /tmp/requirements_clean.txt || true; \
        # 过滤冲突或超大依赖
        gawk 'BEGIN{IGNORECASE=1} \
            !/^torch([[:space:]=<>+.-].*)?$/ && \
            $0 !~ /^torchvision/ && \
            $0 !~ /^torchaudio/ && \
            $0 !~ /^xformers/ && \
            $0 !~ /^onnxruntime/ && \
            $0 !~ /^triton/ && \
            $0 !~ /^tensorrt/ && \
            $0 !~ /^nvidia-/ {print}' \
            /tmp/requirements_clean.txt > /tmp/requirements_runtime.txt; \
        echo "Filtered runtime requirements (first 120 lines):"; head -n 120 /tmp/requirements_runtime.txt || true; \
        if [ -s /tmp/requirements_runtime.txt ]; then \
            PIP_OPTS="--no-cache-dir --prefer-binary --default-timeout=120"; \
            pip install $PIP_OPTS -r /tmp/requirements_runtime.txt -v || { \
                echo "pip install failed. Showing filtered requirements to help debug:"; \
                cat /tmp/requirements_runtime.txt; \
                echo "Retry per-package to identify failures..."; \
                FAILED=0; \
                while IFS= read -r pkg || [ -n "$pkg" ]; do \
                    [ -z "$pkg" ] && continue; \
                    echo ">>> Installing: $pkg"; \
                    pip install $PIP_OPTS "$pkg" || { echo "### FAILED: $pkg"; FAILED=1; }; \
                done < /tmp/requirements_runtime.txt; \
                [ "$FAILED" -eq 0 ] || { echo "Some packages failed to install (see ### FAILED above)"; exit 1; }; \
            }; \
        else \
            echo "Filtered requirements list is empty. Skipping pip install."; \
        fi; \
    fi; \
    rm -f /tmp/requirements_all.txt /tmp/requirements_clean.txt /tmp/requirements_runtime.txt

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

# ---- 解压/重命名/软链 对齐工作流节点默认名 ----
WORKDIR $COMBERT_DIR/models/insightface/models/
RUN unzip -o buffalo_l.zip -d buffalo_l && rm -f buffalo_l.zip

WORKDIR $COMBERT_DIR
# VAE: sdxl_vae.safetensors -> sdxl.vae.safetensors  (AV_VAELoader 期望)  :contentReference[oaicite:6]{index=6}
RUN ln -sf models/vae/sdxl_vae.safetensors models/vae/sdxl.vae.safetensors

# Checkpoint: RealVisXL_* -> realvisxlV50_v50LightningBakedvae.safetensors (CheckpointLoaderSimple 期望)  :contentReference[oaicite:7]{index=7}
RUN ln -sf models/checkpoints/RealVisXL_V5.0_Lightning_fp16.safetensors \
       models/checkpoints/realvisxlV50_v50LightningBakedvae.safetensors

# ---- templates 配置与文件放置 ----
# 客户要求重映射到 Linux 路径，并确保 templates 目录存在。  :contentReference[oaicite:8]{index=8}
RUN mkdir -p templates/FullAIGroupWikinger && \
    mkdir -p custom_nodes/ComfyUI-Custom-Scripts/user && \
    printf '{\n  "input": "$input/**/*.txt",\n  "output": "$output/**/*.txt",\n  "temp": "$temp/**/*.txt",\n  "templates": "/workspace/ComfyUI/templates/**/*.txt"\n}\n' \
      > custom_nodes/ComfyUI-Custom-Scripts/user/text_file_dirs.json

# 将你上传的 Prompt.txt 放到工作流引用的位置；同时放置空的 Negativ.txt 以免节点报缺失。  :contentReference[oaicite:9]{index=9} :contentReference[oaicite:10]{index=10}
COPY --chown=root:root ./Prompt.txt templates/FullAIGroupWikinger/Prompt.txt
RUN test -f templates/FullAIGroupWikinger/Negativ.txt || touch templates/FullAIGroupWikinger/Negativ.txt

# 可选：若你想兼容 JSON 里的 Windows 示例图像路径，可在容器里创建软链到 Linux 路径（如果你会放一张样图到 templates/Sampleimages/gruppe.jpg）
# RUN mkdir -p templates/Sampleimages && \
#     ln -s /workspace/ComfyUI/templates/Sampleimages/gruppe.jpg /C/AI/API_Server/Templates/Sampleimages/gruppe.jpg || true

# 回到默认工作目录
WORKDIR /
