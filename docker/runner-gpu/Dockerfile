# GPU-enabled runner image for PyTorch CI
# Based on runner-base with NVIDIA CUDA support

FROM ubuntu:22.04 AS base

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-pip \
    python3-venv \
    wget \
    unzip \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA CUDA (CUDA 12.1 for PyTorch 2.x compatibility)
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb \
    && dpkg -i cuda-keyring_1.0-1_all.deb \
    && rm cuda-keyring_1.0-1_all.deb \
    && apt-get update \
    && apt-get install -y \
    cuda-toolkit-12-1 \
    libcudnn8 \
    libcudnn8-dev \
    && rm -rf /var/lib/apt/lists/*

# Set CUDA environment variables
ENV PATH=/usr/local/cuda-12.1/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.1/lib64:${LD_LIBRARY_PATH}
ENV CUDA_HOME=/usr/local/cuda-12.1

# Install Docker CLI with NVIDIA runtime support
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Container Toolkit (for docker GPU access)
RUN distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
    && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
       sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
       tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
    && apt-get update \
    && apt-get install -y nvidia-container-toolkit \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions Runner
ARG RUNNER_VERSION=2.313.0
RUN useradd -m -s /bin/bash runner \
    && mkdir -p /home/runner/actions-runner \
    && cd /home/runner/actions-runner \
    && curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
       -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && chown -R runner:runner /home/runner/actions-runner

# Install runner dependencies
RUN cd /home/runner/actions-runner && ./bin/installdependencies.sh

# Set up workspace directory
RUN mkdir -p /home/runner/work && chown -R runner:runner /home/runner/work

# Install PyTorch build dependencies
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    ccache \
    libopenblas-dev \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages commonly needed for PyTorch CI
RUN python3 -m pip install --no-cache-dir \
    numpy \
    pyyaml \
    setuptools \
    cffi \
    typing_extensions \
    sympy \
    filelock \
    networkx \
    jinja2 \
    fsspec

USER runner
WORKDIR /home/runner/actions-runner

# Set environment to indicate GPU support
ENV PYTORCH_RUNNER_GPU=1

# Runner will be configured at runtime
ENTRYPOINT ["/home/runner/actions-runner/bin/Runner.Listener"]
CMD ["run"]
