#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-/opt/guacamole}"
STAGING="${STAGING:-${ROOT_DIR}/dist/macos}"
ARCH="$(uname -m)"
VERSION="$(grep -E '^AC_INIT' "${ROOT_DIR}/configure.ac" | sed -E 's/.*, \[(.*)\]\)/\1/')"

brew_prefix() {
    brew --prefix "$1"
}

BREW="$(brew --prefix)"
export PKG_CONFIG_PATH="${BREW}/lib/pkgconfig:$(brew_prefix jpeg)/lib/pkgconfig:$(brew_prefix webp)/lib/pkgconfig"
export CPPFLAGS="-I${BREW}/include -I$(brew_prefix jpeg)/include -I$(brew_prefix webp)/include -Wno-error=unused-variable"
export LDFLAGS="-L${BREW}/lib -L$(brew_prefix jpeg)/lib -L$(brew_prefix webp)/lib"

cd "${ROOT_DIR}"

autoreconf -fi

./configure \
    --prefix="${PREFIX}" \
    --disable-guacd \
    --disable-guaclog \
    --disable-kubernetes \
    --without-rdp \
    --without-ssh \
    --without-vnc \
    --without-telnet \
    --without-terminal \
    --without-pulse

make -j"$(sysctl -n hw.ncpu)" -C src/libguac
make -j"$(sysctl -n hw.ncpu)" -C src/guacenc
make install -C src/libguac DESTDIR="${STAGING}"
make install -C src/guacenc DESTDIR="${STAGING}"

GUACENC="${STAGING}${PREFIX}/bin/guacenc"
LIB_DIR="${STAGING}${PREFIX}/lib"

PACKAGE_NAME="guacenc-${VERSION}-macos-${ARCH}"
PACKAGE_DIR="${ROOT_DIR}/dist/${PACKAGE_NAME}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/bin" "${PACKAGE_DIR}/lib"

cp "${GUACENC}" "${PACKAGE_DIR}/bin/"
cp "${LIB_DIR}"/libguac*.dylib "${PACKAGE_DIR}/lib/"

LIBGUAC="$(echo "${PACKAGE_DIR}"/lib/libguac.*.dylib | tr ' ' '\n' | grep -E 'libguac\.[0-9]+\.dylib$' | head -1)"
LIBGUAC_NAME="$(basename "${LIBGUAC}")"

install_name_tool -id "@rpath/${LIBGUAC_NAME}" "${LIBGUAC}"
install_name_tool -change "${PREFIX}/lib/${LIBGUAC_NAME}" "@executable_path/../lib/${LIBGUAC_NAME}" "${PACKAGE_DIR}/bin/guacenc"
install_name_tool -add_rpath "@executable_path/../lib" "${PACKAGE_DIR}/bin/guacenc" 2>/dev/null || true

cat > "${PACKAGE_DIR}/README.txt" <<EOF
guacenc ${VERSION} for macOS (${ARCH})

Install FFmpeg and image libraries before running:

  brew install ffmpeg cairo jpeg libpng webp ossp-uuid

Usage:

  guacenc /path/to/recording.guac

Output is written alongside the input as recording.guac.m4v

The build script installs guacenc to your PATH by default (Homebrew prefix).
Skip with: INSTALL_TO_PATH=0 ./scripts/build-guacenc-macos.sh
EOF

tar -C "${ROOT_DIR}/dist" -czf "${ROOT_DIR}/dist/${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}"

echo "Built ${ROOT_DIR}/dist/${PACKAGE_NAME}.tar.gz"

if [ "${INSTALL_TO_PATH:-1}" != "0" ] && [ "${CI:-}" != "true" ]; then
    INSTALL_PREFIX="${INSTALL_PREFIX:-$(brew --prefix)}"
    INSTALL_BIN="${INSTALL_PREFIX}/bin"
    INSTALL_LIB="${INSTALL_PREFIX}/lib"

    mkdir -p "${INSTALL_BIN}" "${INSTALL_LIB}"
    cp "${PACKAGE_DIR}/bin/guacenc" "${INSTALL_BIN}/"
    cp "${PACKAGE_DIR}/lib/"libguac*.dylib "${INSTALL_LIB}/"

    install_name_tool -change "@executable_path/../lib/${LIBGUAC_NAME}" "${INSTALL_LIB}/${LIBGUAC_NAME}" "${INSTALL_BIN}/guacenc"

    echo "Installed guacenc to ${INSTALL_BIN}/guacenc"
fi
