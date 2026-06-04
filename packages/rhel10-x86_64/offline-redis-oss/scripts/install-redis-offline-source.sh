#!/usr/bin/env bash
# Instala Redis OSS desde tarball (sin repos externos).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARBALL="${PKG_ROOT}/source/redis-7.4.8.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="/tmp/redis-build-$$"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ejecutar con sudo o como root." >&2
  exit 1
fi

for cmd in gcc make; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Falta $cmd. Instale 'Development Tools' desde el DVD/ISO de RHEL:" >&2
    echo "  dnf groupinstall 'Development Tools' -y" >&2
    exit 1
  fi
done

echo "==> Extraer fuentes"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
tar xzf "${TARBALL}" -C "${BUILD_DIR}"
cd "${BUILD_DIR}"/redis-7.4.8

echo "==> Compilar"
make -j"$(nproc 2>/dev/null || echo 2)"
make install PREFIX="${PREFIX}"

echo "==> Enlaces en PATH"
ln -sf "${PREFIX}/bin/redis-server" /usr/local/bin/redis-server 2>/dev/null || true
ln -sf "${PREFIX}/bin/redis-cli" /usr/local/bin/redis-cli 2>/dev/null || true

echo "==> Validación"
"${PREFIX}/bin/redis-server" --version
"${PREFIX}/bin/redis-cli" ping 2>/dev/null || echo "Inicie redis-server manualmente para probar PONG"

rm -rf "${BUILD_DIR}"
echo "Instalación desde fuente completada (prefijo ${PREFIX})."
echo "Cree unit systemd o use redis-server --daemonize yes para PoC."
