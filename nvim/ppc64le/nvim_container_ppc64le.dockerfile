# Use Fedora Rawhide for ppc64le as the base image
FROM fedora:rawhide AS nvim_container_base

# Update and install essential packages
RUN dnf update -y && \
    dnf install -y wget git gcc gcc-c++ \
    make cmake zsh python3 python3-devel \
    python3-pip python3-virtualenv \
    rust cargo \
    zip unzip tar gettext curl \
    java-21-openjdk-devel \
    java-21-openjdk-jmods \
    maven xsel which ripgrep \
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

ENV NODE_VER=20.19.3

# Install Node.js and npm
RUN mkdir -p /nvim && \
    curl -sL "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-ppc64le.tar.gz" | tar -xzC /nvim

ENV PATH="/nvim/node-v${NODE_VER}-linux-ppc64le/bin:$PATH"

RUN npm install -g neovim

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# Install eclipse
# main branch to work around update issue in a toolchain component
RUN cd /nvim && \
    git clone https://github.com/eclipse-jdtls/eclipse.jdt.ls && \
    cd ./eclipse.jdt.ls && \
    ./mvnw clean verify -DskipTests=true

ENV PATH=/nvim/eclipse.jdt.ls/org.eclipse.jdt.ls.product/target/repository/bin:$PATH

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
    git clone --depth 1 --branch v0.11.2 https://github.com/neovim/neovim

# Build depdendencies
RUN cd /nvim/neovim && \
    cmake -S cmake.deps -B .deps -G Ninja -D CMAKE_BUILD_TYPE=RelWithDebInfo -DUSE_BUNDLED=OFF -DUSE_BUNDLED_LIBUV=ON -DUSE_BUNDLED_LPEG=ON -DUSE_BUNDLED_LUA=ON -DUSE_BUNDLED_LUV=ON -DUSE_BUNDLED_LUAJIT=OFF -DUSE_BUNDLED_TS=ON -DUSE_BUNDLED_TS_PARSERS=ON -DUSE_BUNDLED_UNIBILIUM=ON -DUSE_BUNDLED_UTF8PROC=ON && \
    cmake --build .deps

# Build/Install neovim
RUN cd /nvim/neovim && \
    cmake -B build -G Ninja -D CMAKE_BUILD_TYPE=RelWithDebInfo -D CMAKE_INSTALL_PREFIX=/usr && \
    cmake --build build && \
    cmake --install build

# Install lua language server
RUN git clone --depth 1 --branch 3.15.0 https://github.com/LuaLS/lua-language-server /nvim/lua-language-server && \
    cd /nvim/lua-language-server && \
    ./make.sh

ENV PATH="/nvim/lua-language-server/bin:$PATH"

# Install basedpyright
RUN npm install -g basedpyright
