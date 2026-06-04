# Paquete offline — Redis OSS en RHEL 10 (x86_64)

Artefactos para instalar **Redis open source** en servidores **RHEL 10** **sin acceso a Internet**, salvo lo que el cliente permita copiar desde este repositorio.

**Validado:** Redis **7.2.14** (RPM Remi) en RHEL 10.1 x86_64.

---

## Contenido del paquete

| Ruta | Descripción |
|------|-------------|
| `rpms/epel-release-latest-10.noarch.rpm` | Repositorio EPEL 10 (bootstrap) |
| `rpms/remi-release-10.rpm` | Repositorio Remi para EL 10 |
| `rpms/redis-7.2.14-1.module_redis.7.2.el10.remi.x86_64.rpm` | Binarios Redis OSS 7.2.14 |
| `gpg/RPM-GPG-KEY-remi.el10` | Clave GPG de Remi |
| `source/redis-7.4.8.tar.gz` | Código fuente Redis (plan B sin RPM) |
| `meta/SHA256SUMS-*` | Checksums |
| `scripts/install-redis-offline-rpm.sh` | Instalación por RPM (recomendada) |
| `scripts/install-redis-offline-source.sh` | Instalación compilando desde tarball |

**Tamaño aproximado:** ~5 MB (sin contar documentación).

---

## Requisitos en el servidor destino (RHEL 10)

- Arquitectura **x86_64**.
- **RHEL 10** con paquetes base del SO ya instalados (`glibc`, `openssl-libs`, `systemd`, `logrotate`, `shadow-utils`). En instalaciones mínimas, usar el **DVD/ISO de RHEL** local para resolver dependencias antes de instalar Redis.
- Acceso **sudo/root**.
- Copiar esta carpeta completa al servidor (SCP, USB, artefacto de pipeline interno).

---

## Instalación rápida (RPM)

```bash
cd packages/rhel10-x86_64/offline-redis-oss/scripts
sudo ./install-redis-offline-rpm.sh
```

Guía detallada: [`../../../docs/INSTALACION-REDIS-OSS-RHEL10.md`](../../../docs/INSTALACION-REDIS-OSS-RHEL10.md) (sección **Instalación offline**).

---

## Plan B — Compilar desde fuente

Si el RPM falla por dependencias no resueltas offline:

```bash
cd packages/rhel10-x86_64/offline-redis-oss/scripts
sudo ./install-redis-offline-source.sh
```

Requiere grupo **Development Tools** y librerías de desarrollo desde **medio de instalación RHEL** (no incluidas en este paquete).

---

## Verificación

```bash
redis-server --version
redis-cli ping
```

---

## Notas

- **Redis Enterprise** no está incluido (no soportado nativamente en RHEL 10).
- No incluye dependencias completas de **BaseOS** (varios cientos de MB); el servidor RHEL debe tenerlas o instalarlas desde ISO corporativa.
- Para entornos **aarch64**, generar un paquete equivalente (estos RPM son **x86_64**).
