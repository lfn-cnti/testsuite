FROM crystallang/crystal:1.15.1-alpine

RUN apk add --update --no-cache --force-overwrite \
      gc-dev gcc gmp-dev libatomic_ops libevent-static \
      musl-dev pcre-dev yaml-static \
      libxml2-dev openssl-dev openssl-libs-static \
      tzdata yaml-dev zlib-static \
      make git \
      llvm11-dev llvm11-static g++

RUN git config --global --add safe.directory /workspace

CMD ["/bin/sh"]
