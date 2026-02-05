# Base runner image with common tools
FROM ubuntu:22.04

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
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for docker-in-docker support)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
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

# Install common development tools
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    ccache \
    && rm -rf /var/lib/apt/lists/*

USER runner
WORKDIR /home/runner/actions-runner

# Runner will be configured at runtime
ENTRYPOINT ["/home/runner/actions-runner/bin/Runner.Listener"]
CMD ["run"]
