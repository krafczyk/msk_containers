# Use Fedora Rawhide for x86 as the base image
FROM quay.io/fedora/fedora:43@sha256:a08659cad3f9c8279e70bea1feee02162a1751bda3103c55ba437707fa8efeca AS nvim_container_base

# Update and install essential packages
RUN dnf update -y && \
    dnf install -y wget git gcc gcc-c++ \
    make cmake zsh python3 python3-devel \
    python3-pip python3-virtualenv \
    rust cargo gh \
    zip unzip tar gettext curl \
    java-21-openjdk-devel \
    java-21-openjdk-jmods \
    maven xclip which ripgrep pgrep \
    procps-ng iproute lsof \
    glibc-locale-source \
    glibc-langpack-en \
    glibc-gconv-extra \
    ninja-build \
    libstdc++-static \
    libvterm libvterm-devel \
    msgpack msgpack-devel \
    clangd redhat-rpm-config libffi-devel \
    openssl-devel && \
    dnf clean all

# Generate the locales
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

# Install needed python packages
RUN pip3 install --prefix /usr \
    "git+https://github.com/pydantic/pydantic@main#egg=pydantic" \
    openai jedi pynvim python-lsp-server[all]

ENV NODE_VER=22.22.3
ENV MSK_CONTAINER_ARCH=x86_64
ENV MSK_NODE_GLOBAL_KEY=node-v22

# A read-only image still needs a stable target for the runtime-owned npm
# prefix bind mount.
RUN mkdir -p /opt/msk/npm-global

# Install Node.js and npm
RUN mkdir -p /nvim && \
    curl -sL "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.gz" | tar -xzC /nvim

ENV PATH="/nvim/node-v${NODE_VER}-linux-x64/bin:$PATH"

RUN npm install -g neovim

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# Install eclipse
# main branch to work around update issue in a toolchain component
ENV JDTLS_MILESTONE=1.56.0
RUN set -eux;  cd /nvim; \
    base="https://download.eclipse.org/jdtls/milestones/${JDTLS_MILESTONE}"; \
    file="$(curl -fsSL ${base}/latest.txt | tr -d '\n')"; \
    curl -fsSLO "${base}/${file}"; \
    curl -fsSLO "${base}/${file}"; \
    sum="$(curl -fsSL "${base}/${file}.sha256" \
        | tr -d '\r' \
        | grep -Eo '[0-9a-fA-F]{64}' \
        | head -n1)"; \
    test -n "${sum}"; \
    echo "${sum}  ${file}" | sha256sum -c -; \
    mkdir -p /nvim/jdtls; \
    tar --no-same-owner --no-same-permissions -xzf "${file}" -C /nvim/jdtls --strip-components=1

ENV PATH=/nvim/jdtls/bin:$PATH

# Build/install LuaJit
RUN cd /nvim && \
    #git clone --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT && \
    git clone --depth 1 --branch v2.1-agentzh https://github.com/openresty/luajit2 && \
    cd luajit2 && \
    sed -i s@/usr/local@/usr@ Makefile && \
    make && \
    make install

# Update ldconfig
RUN echo "/usr/lib" > /etc/ld.so.conf.d/usr-lib.conf && \
    ldconfig

# Clone neovim
RUN cd /nvim && \
    git clone --depth 1 --branch v0.12.4 https://github.com/neovim/neovim

# Build dependencies
RUN cd /nvim/neovim && \
    cmake -S cmake.deps -B .deps -G Ninja \
      -D CMAKE_BUILD_TYPE=RelWithDebInfo \
      -DUSE_BUNDLED=ON && \
    cmake --build .deps

# Build/Install neovim
RUN cd /nvim/neovim && \
    cmake -B build -G Ninja \
      -D CMAKE_BUILD_TYPE=RelWithDebInfo \
      -D CMAKE_INSTALL_PREFIX=/usr && \
    cmake --build build && \
    cmake --install build

# Install lua language server
RUN git clone --depth 1 --branch 3.17.1 https://github.com/LuaLS/lua-language-server /nvim/lua-language-server && \
    cd /nvim/lua-language-server && \
    bash ./make.sh

ENV PATH="/nvim/lua-language-server/bin:$PATH"

# Baseline tools make a fresh MkChad launch work before a user-managed runtime
# update has been installed.  The latter takes precedence when mounted.
ARG OPENCODE_VERSION=1.17.20
RUN npm install -g basedpyright "opencode-ai@${OPENCODE_VERSION}"
