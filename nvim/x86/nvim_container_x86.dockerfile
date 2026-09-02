# Use the Docker Official Fedora 43 multi-architecture image pinned by index digest.
FROM docker.io/library/fedora:43@sha256:762d73ba1c455232b0272c5d445a34f36c4b9f421cbc05ce8102552325b6a222 AS nvim_container_base

# Update and install essential packages
RUN dnf update -y && \
    dnf install -y wget git gcc gcc-c++ \
    bubblewrap libtalloc-devel pkgconf-pkg-config \
    musl-gcc musl-devel musl-libc-static \
    make cmake zsh python3 python3-devel \
    python3-pip python3-virtualenv \
    rust cargo luarocks gh \
    zip unzip tar gettext curl jq ShellCheck shfmt uv \
    java-21-openjdk-devel \
    java-21-openjdk-jmods \
    maven xclip which ripgrep pgrep \
    time hyperfine strace perf \
    procps-ng iproute lsof sqlite openssh-clients \
    xdg-utils ffmpeg-free chromium chromium-headless chromedriver \
    nss-tools xorg-x11-server-Xvfb \
    google-noto-sans-fonts google-noto-color-emoji-fonts \
    glibc-locale-source \
    glibc-langpack-en \
    glibc-gconv-extra \
    ninja-build \
    libstdc++-static \
    libvterm libvterm-devel \
    msgpack msgpack-devel \
    clang clangd redhat-rpm-config libffi-devel \
    openssl-devel memray age && \
    age --version && \
    age-keygen --version && \
    shfmt --version && \
    uv --version && \
    dnf clean all

# Declare this before later tool paths to preserve their runtime precedence.
ENV PATH="/opt/msk/container-tools/bin:$PATH"

# Generate the locales
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

# A read-only image needs stable build and runtime-owned npm directories.
RUN mkdir -p /nvim /opt/msk/npm-global

ARG PROOT_VERSION=v5.4.0
ARG PROOT_REVISION=bd5a5f63d72f8210d8cee76195eb9f0749e5bd70
ARG PROOT_UTHASH_REVISION=e493aa90a2833b4655927598f169c31cfcdf7861
# PRoot derives its version from Git refs, so retain only the verified release tag.
RUN set -eux; \
    git clone --depth 1 --single-branch --branch "${PROOT_VERSION}" \
      https://github.com/proot-me/proot.git /tmp/proot; \
    git -C /tmp/proot checkout --detach "${PROOT_REVISION}"; \
    test "$(git -C /tmp/proot rev-parse HEAD)" = "${PROOT_REVISION}"; \
    test "$(git -C /tmp/proot ls-tree --object-only HEAD lib/uthash)" = "${PROOT_UTHASH_REVISION}"; \
    git -C /tmp/proot submodule update --init lib/uthash; \
    test "$(git -C /tmp/proot/lib/uthash rev-parse HEAD)" = "${PROOT_UTHASH_REVISION}"; \
    make -C /tmp/proot/src proot; \
    install -D -m 0755 /tmp/proot/src/proot /opt/msk/proot/bin/proot; \
    install -D -m 0644 /tmp/proot/COPYING /opt/msk/proot/licenses/proot/COPYING; \
    install -D -m 0644 /tmp/proot/lib/uthash/LICENSE /opt/msk/proot/licenses/uthash/LICENSE; \
    ln -s /opt/msk/proot/bin/proot /usr/bin/proot; \
    rm -rf /tmp/proot; \
    bwrap --version; \
    test -x /opt/msk/proot/bin/proot; \
    test -L /usr/bin/proot; \
    test "$(readlink /usr/bin/proot)" = /opt/msk/proot/bin/proot; \
    test -f /opt/msk/proot/licenses/proot/COPYING; \
    test -f /opt/msk/proot/licenses/uthash/LICENSE; \
    proot --version | grep -Eq " ${PROOT_VERSION}(-[0-9a-f]{8})?$"; \
    smoke_dir=/tmp/msk-proot-smoke; \
    mkdir -p "${smoke_dir}"; \
    printf '%s\n' '#include <stdio.h>' 'int main(void) { puts("hello"); return 0; }' > "${smoke_dir}/hello.c"; \
    musl-gcc -std=c11 -static "${smoke_dir}/hello.c" -o "${smoke_dir}/hello"; \
    LC_ALL=C readelf -lW "${smoke_dir}/hello" > "${smoke_dir}/program-headers"; \
    ! grep -Fq ' INTERP ' "${smoke_dir}/program-headers"; \
    "${smoke_dir}/hello"; \
    rm -rf "${smoke_dir}"

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
      -DUSE_BUNDLED=ON \
      -DUSE_BUNDLED_LUAJIT=OFF && \
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

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# Install Eclipse JDTLS
ENV JDTLS_MILESTONE=1.56.0
RUN set -eux;  cd /nvim; \
    base="https://download.eclipse.org/jdtls/milestones/${JDTLS_MILESTONE}"; \
    file="$(curl -fsSL ${base}/latest.txt | tr -d '\n')"; \
    curl -fsSLO "${base}/${file}"; \
    sum="$(curl -fsSL "${base}/${file}.sha256" \
        | tr -d '\r' \
        | grep -Eo '[0-9a-fA-F]{64}' \
        | head -n1)"; \
    test -n "${sum}"; \
    echo "${sum}  ${file}" | sha256sum -c -; \
    mkdir -p /nvim/jdtls; \
    tar --no-same-owner --no-same-permissions -xzf "${file}" -C /nvim/jdtls; \
    test -x /nvim/jdtls/bin/jdtls

ARG STYLUA_VERSION=2.5.2
ARG AST_GREP_VERSION=0.44.1
ARG LUACHECK_VERSION=1.2.0-1
RUN cargo install --locked --root /usr --version "${STYLUA_VERSION}" \
      --features luajit stylua && \
    cargo install --locked --root /opt/msk/ast-grep --version "${AST_GREP_VERSION}" \
      ast-grep && \
    ln -s /opt/msk/ast-grep/bin/ast-grep /usr/bin/ast-grep && \
    luarocks install luacheck "${LUACHECK_VERSION}"

# Install needed python packages
RUN pip3 install --prefix /usr \
    "git+https://github.com/pydantic/pydantic@main#egg=pydantic" \
    openai jedi pynvim python-lsp-server[all] "jsonschema>=4.23,<5" \
    selenium==4.46.0 \
    py-spy && \
    python3 -c 'from jsonschema import Draft202012Validator' && \
    ast-grep --version && \
    ffmpeg -version && \
    shellcheck --version

ENV NODE_VER=24.18.0

# Install Node.js and npm
RUN curl -sL "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.gz" | tar -xzC /nvim

ENV PATH="/nvim/node-v${NODE_VER}-linux-x64/bin:$PATH"

RUN npm install -g neovim

ENV PATH=/nvim/jdtls/bin:$PATH

ENV PATH="/nvim/lua-language-server/bin:$PATH"

ARG AGENT_BROWSER_VERSION=0.32.2
ARG PLAYWRIGHT_VERSION=1.61.1
ARG OPENCODE_PLAYWRIGHT_VERSION=1.59.1
ARG PUPPETEER_VERSION=25.3.0
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/msk/playwright-browsers
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium-browser
RUN npm install -g basedpyright \
      "agent-browser@${AGENT_BROWSER_VERSION}"

RUN npm install --prefix /opt/msk/browser-tools --save-exact \
       "@playwright/test@${PLAYWRIGHT_VERSION}" \
       "puppeteer@${PUPPETEER_VERSION}" && \
    npm install --prefix /opt/msk/opencode-playwright --save-exact \
       "@playwright/test@${OPENCODE_PLAYWRIGHT_VERSION}" && \
    ln -s /opt/msk/browser-tools/node_modules /node_modules && \
    ln -s /opt/msk/browser-tools/node_modules/.bin/playwright /usr/bin/playwright && \
    ln -s /opt/msk/browser-tools/node_modules/.bin/puppeteer /usr/bin/puppeteer && \
    playwright install chromium && \
    /opt/msk/opencode-playwright/node_modules/.bin/playwright install chromium && \
    agent-browser --version

# Bun supports source authoring and testing; OpenCode uses its verified release.
ARG BUN_VERSION=1.3.14
ARG BUN_RELEASE_BASE=https://github.com/oven-sh/bun/releases/download/bun-v1.3.14
ARG BUN_ASSET=bun-linux-x64.zip
ARG BUN_SHA256=951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f
RUN set -eux; \
    bun_archive="/tmp/${BUN_ASSET}"; \
    bun_extract="/tmp/bun"; \
    curl --fail --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --retry-max-time 1800 --proto '=https' --tlsv1.2 --output "${bun_archive}" \
      "${BUN_RELEASE_BASE}/${BUN_ASSET}"; \
    echo "${BUN_SHA256}  ${bun_archive}" | sha256sum --check --strict -; \
    unzip -q "${bun_archive}" -d "${bun_extract}"; \
    install -D -m 0755 "${bun_extract}/${BUN_ASSET%.zip}/bun" /opt/msk/bun/bin/bun; \
    ln -s /opt/msk/bun/bin/bun /usr/bin/bun; \
    ln -s /opt/msk/bun/bin/bun /usr/bin/bunx; \
    rm -rf "${bun_archive}" "${bun_extract}"; \
    test "$(bun --version)" = "${BUN_VERSION}"; \
    test "$(bunx --version)" = "${BUN_VERSION}"

# Build/install container-tools
RUN set -eux; \
    git clone https://github.com/krafczyk/container_tools.git /tmp/container-tools; \
    git -C /tmp/container-tools checkout --detach b03c42a2965c3d9c2696662b6928a113c4d698f3; \
    test "$(git -C /tmp/container-tools rev-parse HEAD)" = b03c42a2965c3d9c2696662b6928a113c4d698f3; \
    cmake -S /tmp/container-tools -B /tmp/container-tools-build \
      -D CMAKE_BUILD_TYPE=Release -D CONTAINER_TOOLS_STATIC=ON \
      -D CMAKE_C_COMPILER=musl-gcc; \
    cmake --build /tmp/container-tools-build; \
    cmake --install /tmp/container-tools-build --prefix /opt/msk/container-tools; \
    /opt/msk/container-tools/bin/container-tools --version | grep -Fq b03c42a2965c3d9c2696662b6928a113c4d698f3; \
    /opt/msk/container-tools/bin/container-tools --version --json | grep -Fq '"source_commit":"b03c42a2965c3d9c2696662b6928a113c4d698f3"'; \
    /opt/msk/container-tools/bin/container-tools --version --json | grep -Fq '"mount_plan_grammar":"ct-mount-plan-v1"'; \
    rm -rf /tmp/container-tools /tmp/container-tools-build

# Baseline tools make a fresh MkChad launch work before a user-managed runtime
# update has been installed.  The latter takes precedence when mounted.
ARG OPENCODE_VERSION=1.18.18-mkchad.6
ARG OPENCODE_RELEASE_BASE=https://github.com/krafczyk/opencode/releases/download/v1.18.18-mkchad.6
ARG OPENCODE_ASSET=opencode-ai-1.18.18-mkchad.6-linux-x64.tgz
ARG OPENCODE_SHA256=e081e5a8bbf58c144f0e1e7cbf1765de925ecaa16883b51209b3d132593bade5

# Keep the reviewed package in Node's embedded immutable prefix. The mounted
# user prefix remains earlier on PATH at runtime and can intentionally override it.
RUN set -eux; \
    opencode_tarball="/nvim/${OPENCODE_ASSET}"; \
    curl --fail --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 --retry-max-time 1800 --proto '=https' --tlsv1.2 --output "${opencode_tarball}" \
      "${OPENCODE_RELEASE_BASE}/${OPENCODE_ASSET}"; \
    echo "${OPENCODE_SHA256}  ${opencode_tarball}" | sha256sum --check --strict -; \
    test "$(npm prefix --global)" = "/nvim/node-v${NODE_VER}-linux-x64"; \
    npm install -g "${opencode_tarball}"; \
    rm -f "${opencode_tarball}"; \
    test "$(opencode --version)" = "${OPENCODE_VERSION}"

COPY component-manifest.json /usr/share/mkchad/component-manifest.json
