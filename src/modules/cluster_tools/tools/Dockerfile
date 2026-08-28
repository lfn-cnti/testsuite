# cluster-tools: the privileged per-node toolbox the suite runs its node-level
# introspection through (see ClusterTools.exec_by_node). Bump VERSION when
# changing this file; the images workflow publishes ghcr.io/lfn-cnti/cluster-tools.

FROM golang:1.24 AS validator

ENV METRICS_VERSION="main"
RUN git clone -b $METRICS_VERSION https://github.com/prometheus/OpenMetrics.git /validator
WORKDIR /validator/src
RUN make openmetricsvalidator

FROM debian:stable-slim

# renovate: datasource=github-releases depName=kubernetes-sigs/cri-tools
ARG CRI_VERSION=v1.32.0
# renovate: datasource=github-releases depName=opencontainers/runc
ARG RUNC_VERSION=v1.2.6
# renovate: datasource=github-releases depName=containerd/nerdctl
ARG NCTL_VERSION=2.0.4
# renovate: datasource=github-releases depName=containerd/containerd
ARG CTR_VERSION=2.0.4
ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/lfn-cnti/testsuite" \
      org.opencontainers.image.description="CNTi Test Suite cluster-tools: per-node toolbox (crictl, nerdctl, ctr, skopeo, tshark, lsof, strace, OpenMetrics validator)" \
      org.opencontainers.image.licenses="Apache-2.0"

COPY ./sleep /sleep
COPY ./zombie /zombie
COPY --from=validator /validator/bin/openmetricsvalidator /usr/local/bin/

# tshark from Debian instead of a from-source wireshark build: same dissectors
# (NGAP, GTP, PFCP, HTTP/2) for the 5G captures, minutes instead of an hour.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl tshark skopeo sysbench net-tools strace lsof procps && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRI_VERSION}/crictl-${CRI_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin crictl && \
    curl -fsSL -o /usr/local/bin/runc "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${TARGETARCH}" && \
    chmod +x /usr/local/bin/runc && \
    curl -fsSL "https://github.com/containerd/nerdctl/releases/download/v${NCTL_VERSION}/nerdctl-${NCTL_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin nerdctl && \
    curl -fsSL "https://github.com/containerd/containerd/releases/download/v${CTR_VERSION}/containerd-${CTR_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /tmp bin/ctr && \
    mv /tmp/bin/ctr /usr/local/bin/ctr && rmdir /tmp/bin
