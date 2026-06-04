#!/usr/bin/env bash
# Instala Redis OSS 7.2.14 en RHEL 10 sin Internet (RPM Remi incluidos en el repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RPM_DIR="${PKG_ROOT}/rpms"
GPG_KEY="${PKG_ROOT}/gpg/RPM-GPG-KEY-remi.el10"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ejecutar con sudo o como root." >&2
  exit 1
fi

if ! grep -qE 'release 10' /etc/redhat-release 2>/dev/null; then
  echo "Advertencia: este paquete está pensado para RHEL 10.x" >&2
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Error: RPMs incluidos son x86_64; arquitectura actual: $(uname -m)" >&2
  exit 1
fi

echo "==> Importar clave GPG Remi"
rpm --import "${GPG_KEY}"

echo "==> Instalar repositorios bootstrap (EPEL + Remi)"
rpm -Uvh --replacepkgs \
  "${RPM_DIR}/epel-release-latest-10.noarch.rpm" \
  "${RPM_DIR}/remi-release-10.rpm" || true

echo "==> Instalar Redis OSS"
rpm -Uvh "${RPM_DIR}"/redis-7.2.14-*.rpm

echo "==> Habilitar servicio"
systemctl enable redis
systemctl restart redis
sleep 1
systemctl is-active redis

echo "==> Validación"
redis-server --version
redis-cli ping

echo ""
echo "Instalación offline por RPM completada."
echo "Configura /etc/redis/redis.conf.d/ según docs/INSTALACION-REDIS-OSS-RHEL10.md"
