# Matches lovell/sharp's own official linux-x64 CI build environment
# (.github/workflows/ci.yml), so the resulting sharp.node has the same
# glibc-compatibility characteristics as upstream's real prebuilt binaries.
FROM rockylinux/rockylinux:8-ubi-init

RUN dnf install -y epel-release && \
    dnf install -y gcc-toolset-14-gcc-c++ make git python3.12 fontconfig pkgconf tar xz patchelf
ENV PATH="/opt/rh/gcc-toolset-14/root/usr/bin:$PATH"

ARG NODE_VERSION=20.18.3
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar xJC /usr/local --strip-components=1

WORKDIR /work
