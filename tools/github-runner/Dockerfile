# Self-hosted CI runner with the toolchain baked in, so that no shard pays
# for installing Crystal, kind or kustomize. Published by the images workflow
# as ghcr.io/lfn-cnti/github-runner:<runner version>-crystal<Crystal version>.

# renovate: datasource=docker depName=myoung34/github-runner
FROM myoung34/github-runner:2.336.0-ubuntu-noble

# renovate: datasource=github-releases depName=crystal-lang/crystal
ARG CRYSTAL_VERSION=1.19.1
ARG CRYSTAL_URL=https://github.com/crystal-lang/crystal/releases/download
# renovate: datasource=github-releases depName=kubernetes-sigs/kind
ARG KIND_VERSION=v0.32.0
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize versioning=regex:^kustomize/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
ARG KUSTOMIZE_VERSION=v5.8.1

LABEL org.opencontainers.image.source="https://github.com/lfn-cnti/testsuite" \
      org.opencontainers.image.description="CNTi Test Suite self-hosted CI runner: GitHub runner + Crystal, kind, kubectl, helm, kustomize, gh" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg --output /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list && \
    chmod 644 /etc/apt/sources.list.d/github-cli.list

RUN mkdir /crystal && \
    wget -O /crystal/crystal.tar.gz "$CRYSTAL_URL/$CRYSTAL_VERSION/crystal-$CRYSTAL_VERSION-1-linux-x86_64.tar.gz" --progress=dot:giga && \
    tar -xf /crystal/crystal.tar.gz -C /crystal && \
    chmod +x /crystal/crystal-${CRYSTAL_VERSION}-1/bin/crystal && \
    chmod +x /crystal/crystal-${CRYSTAL_VERSION}-1/bin/shards && \
    ln -s /crystal/crystal-${CRYSTAL_VERSION}-1/bin/crystal /usr/local/bin/crystal && \
    ln -s /crystal/crystal-${CRYSTAL_VERSION}-1/bin/shards /usr/local/bin/shards

RUN apt update && \
    apt install -y --no-install-recommends \
    git \
    gh \
    uuid-runtime \
    python3 \
    libssl-dev \
    libxml2-dev \
    libyaml-dev \
    libgmp-dev \
    libevent-dev \
    libpcre2-dev \
    libz-dev && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/python3 /usr/bin/python

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

RUN wget -O /tmp/kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" && \
    tar -xf /tmp/kustomize.tar.gz -C /tmp && \
    install -m 0755 /tmp/kustomize /usr/local/bin/kustomize && \
    rm /tmp/kustomize /tmp/kustomize.tar.gz

RUN curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind
