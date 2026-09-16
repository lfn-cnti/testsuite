FROM ubuntu:jammy-20221130
ARG S6_OVERLAY_VERSION=3.1.3.0

# Install dumb-init
# https://github.com/Yelp/dumb-init
#
RUN sed -i -e 's/^APT/# APT/' -e 's/^DPkg/# DPkg/' \
      /etc/apt/apt.conf.d/docker-clean && \
    apt update && \
    apt install wget nginx xz-utils dumb-init catatonit -y

# Install tini
# https://github.com/krallin/tini
#
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64 /tini
RUN chmod +x /tini

# Install s6-overlay
# https://github.com/just-containers/s6-overlay
#
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz

### Entrypoint and commands for dumb-init
#
# ENTRYPOINT ["/tini", "--"]
# CMD ["nginx", "-g", "daemon off;"]

### Entrypoint and commands for tini
#
# ENTRYPOINT ["/tini", "--"]
# CMD ["nginx", "-g", "daemon off;"]

### Entrypoint and commands for s6-overlay
#
# ENTRYPOINT ["/init"]
# CMD ["nginx", "-g", "daemon off;"]
