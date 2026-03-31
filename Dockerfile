FROM ubuntu:22.04

ARG RUNNER_VERSION=2.333.0
ARG DEBIAN_FRONTEND=noninteractive

# ── Core dependencies ──
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    sudo \
    unzip \
    wget \
    bc \
    python3 \
    openjdk-17-jdk \
    maven \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# ── Create runner user ──
RUN useradd -m -s /bin/bash runner && \
    usermod -aG sudo runner && \
    usermod -aG docker runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Install GitHub Actions Runner ──
WORKDIR /home/runner/actions-runner
RUN curl -o actions-runner.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" && \
    tar xzf actions-runner.tar.gz && \
    rm actions-runner.tar.gz && \
    ./bin/installdependencies.sh && \
    chown -R runner:runner /home/runner

# ── Disable auto-update (version controlled via image rebuild) ──
ENV AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
RUN mkdir -p /opt/hostedtoolcache && chown runner:runner /opt/hostedtoolcache

# ── Entrypoint script ──
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
