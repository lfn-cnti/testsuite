FROM golang:1.16 AS validator
ENV METRICS_VERSION="main"
RUN git clone -b $METRICS_VERSION https://github.com/OpenObservability/OpenMetrics.git /validator
WORKDIR /validator/src
RUN make openmetricsvalidator

FROM debian:stable-slim as wireshark_build

# INSTALL Wireshark
RUN apt update && apt-get install -y build-essential git cmake bison flex libgtk-3-dev libpcap-dev libssl-dev libncurses5-dev qtbase5-dev qttools5-dev-tools qttools5-dev libqt5svg5-dev libtool libgcrypt20-dev libc-ares-dev

RUN git clone https://github.com/wireshark/wireshark.git /wireshark
RUN cd /wireshark && \
    git checkout tags/wireshark-4.0.8 && \
    mkdir build && \
    cd build && \
    cmake ../ && \
    make -j`nproc` && \
    make install

FROM debian:stable-slim
ENV CRI_VERSION="v1.17.0"
ENV CTR_VERSION="1.5.0"
ENV RUNC_VERSION="v1.1.4"
ENV CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
ENV IMAGE_SERVICE_ENDPOINT=unix:///run/containerd/containerd.sock

COPY ./sleep /sleep
COPY ./zombie /zombie

COPY --from=wireshark_build /usr/local /usr/local
COPY --from=validator /validator/bin/openmetricsvalidator /usr/local/bin/
RUN apt update && apt install -y curl sysbench skopeo net-tools strace libpcap-dev libssl-dev libc-ares-dev libqt5printsupport5

RUN curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRI_VERSION}/crictl-${CRI_VERSION}-linux-amd64.tar.gz --output crictl-${CRI_VERSION}-linux-amd64.tar.gz && \
    tar zxvf crictl-$CRI_VERSION-linux-amd64.tar.gz -C /usr/local/bin && \
    rm -f crictl-$CRI_VERSION-linux-amd64.tar.gz

RUN curl -L https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.amd64 --output /usr/local/bin/runc && chmod +x /usr/local/bin/runc

RUN curl -L https://github.com/containerd/nerdctl/releases/download/v1.2.1/nerdctl-1.2.1-linux-amd64.tar.gz --output nerdctl.tar.gz && \
    tar zxvf nerdctl.tar.gz -C /tmp/ && \
    mv /tmp/nerdctl /usr/local/bin/ && \
    rm -f  nerdctl.tar.gz


RUN curl -L https://github.com/containerd/containerd/releases/download/v${CTR_VERSION}/containerd-${CTR_VERSION}-linux-amd64.tar.gz --output containerd-${CTR_VERSION}-linux-amd64.tar.gz && \
    tar zxvf containerd-${CTR_VERSION}-linux-amd64.tar.gz -C /tmp/ && \
    mv /tmp/bin/ctr /usr/local/bin && \
    rm -f containerd-${CTR_VERSION}-linux-amd64.tar.gz


