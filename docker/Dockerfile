ARG BASE_IMAGE=ubuntu:22.04

FROM ${BASE_IMAGE}

LABEL maintainer="Roman Zashchitin <roman.zashchitin@gmail.com>"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# Base system packages and locales
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        apt-utils \
        ca-certificates \
        curl \
        gnupg2 \
        locales \
        lsb-release \
        tzdata \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=$LC_ALL LANG=$LANG \
    && rm -rf /var/lib/apt/lists/*

# Development tooling, X11/Wayland/Mesa stack and audio
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        cmake \
        gfortran \
        git \
        libopenblas-dev \
        # mesa-utils \
        python3-pip \
        unzip \
        vim \
        wget \
        # X11 libraries (+32-bit counterparts)
        libxau6 libxau6:i386 \
        libxdmcp6 libxdmcp6:i386 \
        libxcb1 libxcb1:i386 \
        libxext6 libxext6:i386 \
        libx11-6 libx11-6:i386 \
        # Wayland/Gtk stack
        libwayland-client0 \
        libwayland-cursor0 \
        libwayland-egl1 \
        libwayland-server0 \
        libxkbcommon0 \
        libgtk-3-0 \
        libgdk-pixbuf2.0-0 \
        libcairo-gobject2 \
        libpango-1.0-0 \
        libatk1.0-0 \
        # Audio support
        pulseaudio \
        libpulse0 \
        # OpenGL/Vulkan userspace
        libglvnd0 libglvnd0:i386 \
        # libgl1 libgl1:i386 \
        # libglx0 libglx0:i386 \
        # libegl1 libegl1:i386 \
        # libgles2 libgles2:i386 \
        # mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

# GPU-aware entrypoint ensures proper vendor selection when NVIDIA runtime is used
RUN install -d /usr/local/bin \
    && cat >/usr/local/bin/gpu-entrypoint.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log() {
    echo "[gpu-entrypoint] $*"
}

add_vendor_dir() {
    local dir="$1"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        return
    fi
    for existing in "${vendor_dirs[@]:-}"; do
        if [[ "$existing" == "$dir" ]]; then
            return
        fi
    done
    vendor_dirs+=("$dir")
}

link_gl_libs() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \
        \( -name 'libGL*.so*' \
        -o -name 'libEGL*.so*' \
        -o -name 'libGLES*.so*' \
        -o -name 'libcuda.so*' \
        -o -name 'libnvidia-*.so*' \
        -o -name 'libnvoptix.so*' \) -print0 \
        | while IFS= read -r -d '' lib; do
            local target="/usr/lib/x86_64-linux-gnu/$(basename "$lib")"
            if [[ -e "$target" && ! -L "$target" ]]; then
                log "пропускаю перезапись $target"
                continue
            fi
            ln -sfn "$lib" "$target"
        done
}

vendor_dirs=()
add_vendor_dir "/usr/local/nvidia/lib"
add_vendor_dir "/usr/local/nvidia/lib64"
add_vendor_dir "${WSL_GPU_LIB_DIR:-}"
add_vendor_dir "/usr/lib/wsl/lib"

use_nvidia=0
if [[ -n "${NVIDIA_VISIBLE_DEVICES:-}" && "${NVIDIA_VISIBLE_DEVICES}" != "void" ]]; then
    use_nvidia=1
fi
if [[ ${#vendor_dirs[@]} -gt 0 ]]; then
    use_nvidia=1
fi

if [[ ${use_nvidia} -eq 1 && ${#vendor_dirs[@]} -gt 0 ]]; then
    : > /etc/ld.so.conf.d/nvidia.conf
    extra_ld=""
    for dir in "${vendor_dirs[@]}"; do
        echo "$dir" >> /etc/ld.so.conf.d/nvidia.conf
        if [[ -z "$extra_ld" ]]; then
            extra_ld="$dir"
        else
            extra_ld="${extra_ld}:$dir"
        fi
        link_gl_libs "$dir"
    done

    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        export LD_LIBRARY_PATH="${extra_ld}:${LD_LIBRARY_PATH}"
    else
        export LD_LIBRARY_PATH="${extra_ld}"
    fi

    export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
    export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
    export __VK_LAYER_NV_optimus="${__VK_LAYER_NV_optimus:-1}"
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER="${__NV_PRIME_RENDER_OFFLOAD_PROVIDER:-NVIDIA-G0}"

    log "NVIDIA GPU detected (каталоги: ${vendor_dirs[*]})"
else
    rm -f /etc/ld.so.conf.d/nvidia.conf
    log "using Mesa stack"
fi

ldconfig

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR=/tmp/runtime-root
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

if [[ $# -eq 0 ]]; then
    exec /bin/bash
else
    exec "$@"
fi
EOF
RUN chmod +x /usr/local/bin/gpu-entrypoint.sh

ENV NVIDIA_VISIBLE_DEVICES="" \
    NVIDIA_DRIVER_CAPABILITIES="graphics,compute,utility"

# Ensure GLVND can locate the NVIDIA vendor implementation when runtime mounts the driver
RUN mkdir -p /usr/share/glvnd/egl_vendor.d /usr/share/glvnd/glx_vendor.d
COPY docker/10_nvidia.json /usr/share/glvnd/egl_vendor.d/10_nvidia.json
COPY docker/10_nvidia_glx.json /usr/share/glvnd/glx_vendor.d/10_nvidia.json

#! ==============================================================
# --- девелопмент + Python 3.10 + MPI ---
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        cmake \
        gfortran \
        git \
        libopenblas-dev \
        python3 \
        python3-dev \
        python3-pip \
        unzip \
        vim \
        wget \
        libopenmpi-dev \
        openmpi-bin \
    && rm -rf /var/lib/apt/lists/*

# --- python зависимости ---
RUN pip3 install --upgrade pip setuptools wheel

RUN pip3 install \
    tensorflow==2.11.1 \
    "numpy>=1.20,<1.24" \
    "scipy>=1.7,<1.11" \
    "tensorboard>=2.11,<2.12" \
    "pandas>=1.3,<1.6" \
    "matplotlib>=3.3,<3.8" \
    numba==0.57.1 \
    attrs==19.3.0 \
    gym==0.17.1 \
    mpi4py==3.1.4 \
    pybullet>=3.0.6 \
    typing==3.7.4.1 \
    stable-baselines==2.10.0 \
    tqdm \
    quadprog \
    inputs \
    opencv-python \
    pillow \
    pyopengl \
    glfw

# Set working directory
WORKDIR /phenix_bullet_ws
# RUN apt-get update && apt-get install -y libgl1 libglib2.0-0


# ENTRYPOINT ENTRYPOINT ["/usr/local/bin/gpu-entrypoint.sh"]
CMD ["/bin/bash"]


  
