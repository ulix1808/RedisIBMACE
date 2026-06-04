# Instalación de Redis OSS en Red Hat Enterprise Linux 10

Guía validada en **RHEL 10.1 (x86_64)** para la PoC **Redis + IBM ACE 12** con Banrural.

> **Contexto:** **Redis Enterprise** no se instala de forma soportada en RHEL 10 (fallos por librerías/binarios no certificados). **Redis open source (OSS)** sí puede instalarse en RHEL 10 usando el repositorio **Remi**, como alternativa de laboratorio/PoC para validar caché con ACE antes de un despliegue Enterprise en OpenShift o RHEL 9.

**Validación ejecutada:** junio 2026 — RHEL 10.1 en AWS EC2 (`t3.micro`, x86_64), Redis **7.2.14** vía `redis:remi-7.2`.

**Paquete offline (sin Internet en el servidor):** [`packages/rhel10-x86_64/offline-redis-oss/`](../packages/rhel10-x86_64/offline-redis-oss/) — RPMs, tarball fuente, scripts y checksums.

---

## 1. Resumen ejecutivo

| Tema | Detalle |
|------|---------|
| **Producto** | Redis OSS (no Redis Enterprise) |
| **Versión instalada** | **7.2.14** (`redis:remi-7.2`) |
| **Repositorio** | EPEL 10 + [Remi for EL 10](https://rpms.remirepo.net/) |
| **Servicio** | `redis.service` (systemd) |
| **Puerto** | 6379 |
| **Compatible con ACE 12** | Sí (Jedis / JavaCompute; ver [`MANUAL-CACHE-REDIS-ACE12.md`](MANUAL-CACHE-REDIS-ACE12.md)) |

---

## 2. Por qué no Redis Enterprise en RHEL 10

Según la [matriz de plataformas de Redis Enterprise](https://redis.io/docs/latest/operate/rs/references/supported-platforms/), las versiones soportadas para instalación on‑prem incluyen **RHEL 8 y RHEL 9**, no **RHEL 10**. En pruebas reales en RHEL 10, el instalador Enterprise puede fallar por **dependencias/librerías** no disponibles o no certificadas para esa versión del SO.

**Redis OSS vía Remi** es un camino distinto: paquetes RPM mantenidos por Remi para EL 10, probados en esta guía.

---

## 3. Prerrequisitos

### 3.1 Sistema

- **RHEL 10.x** (x86_64 recomendado; probado en **10.1 Coughlan**).
- Acceso **root/sudo**.
- Conectividad saliente a Internet (EPEL, Remi, GPG keys).
- **Registro RHEL (recomendado):** con suscripción activa se habilita el repo **CRB** (`crb enable`) sin errores. En instancias de prueba sin registro, la instalación de Redis **puede completarse igual** (validado en EC2 de laboratorio), aunque `subscription-manager` mostrará avisos.

### 3.2 Recursos mínimos (PoC)

| Recurso | Mínimo PoC | Notas |
|---------|------------|--------|
| **RAM** | 1 GB (VM pequeña) | Configurar `maxmemory` acorde (p. ej. 256mb–512mb en `t3.micro`). |
| **CPU** | 2 vCPU | 4+ vCPU si habrá pruebas de carga. |
| **Disco** | 20 GB | Logs, RDB/AOF, SO. |
| **Red** | Puerto **6379** | Security Group / firewall solo hacia hosts ACE. |

### 3.3 Alternativa en repos oficiales RHEL 10

RHEL 10 AppStream puede ofrecer **Valkey** (fork compatible con Redis). Esta guía instala el paquete **`redis`** de Remi cuando se requiere el binario **redis-server** oficial para la PoC.

---

## 4. Instalación offline (sin Internet en RHEL 10)

Para el cliente Banrural: el servidor **no tiene salida a Internet** para descargar paquetes. Este repositorio incluye los **artefactos necesarios** para instalar **solo Redis OSS**.

### 4.1 Contenido del paquete offline

Ruta en el repo clonado:

```text
packages/rhel10-x86_64/offline-redis-oss/
├── rpms/
│   ├── epel-release-latest-10.noarch.rpm
│   ├── remi-release-10.rpm
│   └── redis-7.2.14-1.module_redis.7.2.el10.remi.x86_64.rpm
├── gpg/RPM-GPG-KEY-remi.el10
├── source/redis-7.4.8.tar.gz          # plan B: compilar sin RPM
├── meta/SHA256SUMS-rpms
├── meta/SHA256SUMS-source
└── scripts/
    ├── install-redis-offline-rpm.sh
    └── install-redis-offline-source.sh
```

Verificar integridad en el servidor (opcional):

```bash
cd packages/rhel10-x86_64/offline-redis-oss
sha256sum -c meta/SHA256SUMS-rpms
sha256sum -c meta/SHA256SUMS-source
```

### 4.2 Copiar al servidor RHEL 10

Ejemplo desde una máquina con acceso al repo:

```bash
scp -r packages/rhel10-x86_64/offline-redis-oss ec2-user@<IP_SERVIDOR>:/tmp/
```

O empaquetar:

```bash
tar czf redis-offline-rhel10-x86_64.tgz -C packages/rhel10-x86_64 offline-redis-oss
# transferir redis-offline-rhel10-x86_64.tgz por medio interno
```

### 4.3 Instalación por RPM (recomendada)

En el servidor destino:

```bash
cd /tmp/offline-redis-oss/scripts
sudo ./install-redis-offline-rpm.sh
```

El script:

1. Importa la clave GPG de Remi.  
2. Instala `epel-release` y `remi-release` (metadatos locales; **no requiere** `dnf install` desde Internet si ya se instala el RPM de Redis directamente).  
3. Instala `redis-7.2.14` con `rpm -Uvh`.  
4. Habilita `redis.service` y ejecuta `redis-cli ping`.

**Dependencias:** el RPM de Redis requiere librerías de **RHEL BaseOS** (`glibc`, `openssl-libs`, `systemd`, `logrotate`, `shadow-utils`). Deben estar presentes en la imagen RHEL o instalarse desde el **DVD/ISO corporativo** de RHEL 10 (no incluido en este paquete de ~5 MB).

Si `rpm -Uvh` reporta dependencias faltantes:

```bash
# Ejemplo: instalar desde ISO local de RHEL (ajustar ruta del medio)
sudo dnf install -y logrotate shadow-utils openssl systemd --disablerepo="*" --enablerepo=BaseOS
# o usar plan B (fuente)
```

### 4.4 Plan B — Compilar desde tarball (sin RPM)

Si no se puede instalar el RPM:

```bash
cd /tmp/offline-redis-oss/scripts
sudo ./install-redis-offline-source.sh
```

Requiere **gcc/make** y librerías de desarrollo desde el medio de instalación RHEL (`Development Tools`). Instala binarios en `/usr/local` por defecto.

### 4.5 Qué **no** incluye este paquete

- Redis Enterprise ni operador OpenShift.  
- Repositorio completo de RHEL/EPEL/Remi (solo bootstrap + Redis).  
- Dependencias BaseOS (usar ISO RHEL del cliente).  
- Arquitectura **aarch64** (solo **x86_64** en este bundle).

---

## 5. Instalación en línea (con acceso a repos)

### Paso 1 — Verificar sistema

```bash
cat /etc/redhat-release
uname -m
# Esperado: RHEL 10.x, x86_64
```

### Paso 2 — Instalar EPEL 10 y Remi

```bash
sudo dnf install -y \
  https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
  https://rpms.remirepo.net/enterprise/remi-release-10.rpm
```

Salida esperada: paquetes `epel-release` y `remi-release` instalados.

### Paso 3 — Habilitar repositorio CRB (CodeReady Builder)

Requerido por muchos paquetes EPEL en RHEL:

```bash
sudo crb enable
```

Si el sistema **no está registrado** en Red Hat Subscription Management, puede aparecer un error de `subscription-manager`. En ese caso:

- Registrar la VM con `sudo subscription-manager register`, **o**
- Continuar si `dnf install redis` resuelve dependencias (comportamiento observado en instancia EC2 de prueba sin registro).

### Paso 4 — Elegir stream de Redis en Remi

Listar módulos disponibles:

```bash
sudo dnf module list redis
```

En RHEL 10 (junio 2026), streams típicos:

| Stream Remi | Uso |
|-------------|-----|
| `remi-7.2` | **Recomendado PoC** — Redis 7.2.x (validado) |
| `remi-8.0` … `remi-8.8` | Versiones 8.x si la aplicación lo requiere |

> **Nota:** el stream `remi-7.4` **no existe** en EL 10; no usar documentación genérica que lo cite.

Habilitar e instalar (ejemplo **7.2**):

```bash
sudo dnf module reset redis -y
sudo dnf module enable redis:remi-7.2 -y
sudo dnf install -y redis
```

Verificar:

```bash
redis-server --version
rpm -q redis
# Esperado: Redis server v=7.2.14 ... 
#           redis-7.2.14-1.module_redis.7.2.el10.remi.x86_64
```

---

## 6. Configuración para PoC (caché + ACE)

No editar el archivo monolítico completo; usar un **drop-in** en `/etc/redis/redis.conf.d/`.

### Paso 5 — Archivo de configuración PoC

```bash
sudo mkdir -p /etc/redis/redis.conf.d
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.bak.$(date +%Y%m%d)

sudo tee /etc/redis/redis.conf.d/poc-banrural.conf > /dev/null << 'EOF'
# PoC Banrural - Redis OSS on RHEL 10
bind 0.0.0.0 ::1
protected-mode yes
port 6379
requirepass CAMBIAR_CONTRASEÑA_SEGURA
maxmemory 256mb
maxmemory-policy allkeys-lru
supervised systemd
EOF
```

Asegurar que el archivo principal incluye los drop-ins (al final de `/etc/redis/redis.conf`):

```bash
grep -q 'include /etc/redis/redis.conf.d' /etc/redis/redis.conf || \
  echo 'include /etc/redis/redis.conf.d/*.conf' | sudo tee -a /etc/redis/redis.conf
```

| Parámetro | Valor PoC | Motivo |
|-----------|-----------|--------|
| `bind 0.0.0.0` | Escucha en todas las interfaces | ACE se conecta por red (ajustar si solo red interna). |
| `requirepass` | Contraseña fuerte | Obligatorio si `bind` no es solo localhost. |
| `maxmemory` | 256mb–512mb en VMs pequeñas | Evita OOM en instancias tipo `t3.micro`. |
| `maxmemory-policy` | `allkeys-lru` | Política típica de **caché**. |
| `supervised systemd` | Integración con systemd | Correcto arranque/estado del servicio. |

### Paso 6 — Firewall (si `firewalld` está activo)

```bash
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --reload
```

En **AWS EC2**, abrir también el puerto **6379** en el **Security Group** solo desde las IPs/subredes de los Integration Servers ACE (no exponer a `0.0.0.0/0` en producción).

### Paso 7 — SELinux

En la validación, SELinux estaba en **Enforcing** y Redis arrancó sin cambios adicionales. Si ACE conecta desde otro host y hay denegaciones:

```bash
sudo ausearch -m avc -ts recent | grep redis
# Evaluar booleanos/puertos según política de Banrural
```

### Paso 8 — Habilitar e iniciar servicio

```bash
sudo systemctl enable redis
sudo systemctl restart redis
sudo systemctl status redis
```

Estado esperado: `Active: active (running)` y `Ready to accept connections`.

---

## 7. Validación

### 7.1 Pruebas locales (en el servidor Redis)

```bash
redis-cli -a 'CAMBIAR_CONTRASEÑA_SEGURA' ping
# PONG

redis-cli -a 'CAMBIAR_CONTRASEÑA_SEGURA' \
  SET ace:banrural:poc:test '{"status":"ok","platform":"RHEL10.1"}' EX 3600

redis-cli -a 'CAMBIAR_CONTRASEÑA_SEGURA' GET ace:banrural:poc:test

redis-cli -a 'CAMBIAR_CONTRASEÑA_SEGURA' INFO server | grep -E 'redis_version|os|tcp_port'
```

Resultado validado en RHEL 10.1:

```text
redis_version:7.2.14
os:Linux ... el10_1.x86_64 x86_64
tcp_port:6379
```

### 7.2 Verificar escucha de red

```bash
ss -lntp | grep 6379
# LISTEN ... 0.0.0.0:6379
```

### 7.3 Prueba desde host ACE (remoto)

Desde la VM/servidor donde corre el Integration Server:

```bash
redis-cli -h <IP_REDIS> -p 6379 -a 'CAMBIAR_CONTRASEÑA_SEGURA' ping
```

Si no responde: revisar Security Group, firewall, ruta de red y `bind`/`protected-mode`.

### 7.4 Checklist PoC

- [ ] `redis-server --version` ≥ 7.2 (stream Remi elegido)
- [ ] Servicio `redis` activo en systemd
- [ ] `PING` → `PONG` local
- [ ] SET/GET con clave prefijo `ace:banrural:...` y TTL
- [ ] Conectividad desde red ACE
- [ ] Contraseña documentada en vault/gestor de secretos (no en código BAR)
- [ ] Parámetros cargados en JavaCompute / policy ACE (`redisHost`, `redisPort`, `redisPassword`)

---

## 8. Conexión desde IBM ACE 12

Usar los mismos parámetros en el **JavaCompute** o **User-defined policy** descritos en [`MANUAL-CACHE-REDIS-ACE12.md`](MANUAL-CACHE-REDIS-ACE12.md):

| Propiedad | Ejemplo |
|-----------|---------|
| `redisHost` | IP o DNS interno del servidor Redis |
| `redisPort` | `6379` |
| `redisPassword` | Valor de `requirepass` |
| `defaultTtlSeconds` | `300` (ajustar según negocio) |

Patrón de claves: `ace:<aplicacion>:<recurso>:<id>`.

---

## 9. Operación básica

```bash
# Estado
sudo systemctl status redis

# Logs
sudo journalctl -u redis -f

# Reinicio tras cambio de config
sudo systemctl restart redis

# Estadísticas de caché (PoC)
redis-cli -a '***' INFO stats
redis-cli -a '***' INFO memory
```

---

## 10. Problemas frecuentes

| Síntoma | Causa / acción |
|---------|----------------|
| `missing groups or modules: redis:remi-7.4` | Stream inexistente en EL 10; usar `remi-7.2` u otro listado por `dnf module list redis`. |
| Error al habilitar CRB | VM sin registro RHEL; registrar o probar instalación sin CRB. |
| `PONG` local OK, remoto timeout | Security Group AWS / firewall; no abrir 6379 a Internet innecesariamente. |
| OOM / Redis killed | Subir RAM de VM o bajar `maxmemory`. |
| Redis Enterprise falla en RHEL 10 | Esperado; usar OSS (esta guía) u OpenShift Enterprise ([`DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md`](DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md)). |

---

## 11. Evolución post-PoC

| Objetivo | Camino |
|----------|--------|
| Soporte Enterprise + HA | OpenShift + Redis Operator o RHEL **9** dedicado |
| Mantener OSS en RHEL 10 | Actualizar stream Remi (`dnf module list redis`) |
| Producción | TLS, Sentinel/Cluster, secretos centralizados, monitoreo |

---

## Referencias

- Remi repository: https://rpms.remirepo.net/
- Redis OSS: https://redis.io/docs/
- Redis Enterprise supported platforms: https://redis.io/docs/latest/operate/rs/references/supported-platforms/
- Manual caché ACE 12: [`MANUAL-CACHE-REDIS-ACE12.md`](MANUAL-CACHE-REDIS-ACE12.md)
- OpenShift Operator: [`DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md`](DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md)
