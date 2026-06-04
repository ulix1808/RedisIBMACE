# Redis con IBM App Connect Enterprise 12 (ACE) — guía para PoC

Este repositorio documenta una **prueba de concepto (PoC)** para integrar **Redis** con **IBM App Connect Enterprise 12.x**, usando Redis como **caché** y almacén clave-valor frente a consultas repetidas a una **base de datos tradicional**.

**Manual paso a paso (flujo con caché en ACE 12):** [`docs/MANUAL-CACHE-REDIS-ACE12.md`](docs/MANUAL-CACHE-REDIS-ACE12.md)  
**Redis OSS en RHEL 10 (validado):** [`docs/INSTALACION-REDIS-OSS-RHEL10.md`](docs/INSTALACION-REDIS-OSS-RHEL10.md)  
**Paquete offline Redis OSS (sin Internet):** [`packages/rhel10-x86_64/offline-redis-oss/`](packages/rhel10-x86_64/offline-redis-oss/)  
**Despliegue Redis Enterprise en OpenShift (Operator):** [`docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md`](docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md)

---

## Validación de plataforma: RHEL 10 y Redis Enterprise

**Contexto del cliente (referencia 15 mayo 2026):** el entorno objetivo incluye **Red Hat Enterprise Linux 10**. En la matriz oficial de **Redis Enterprise Software**, Redis documenta soporte para **RHEL 8 y RHEL 9** (y clones compatibles con ABI RHEL). **RHEL 10 no figura** como plataforma soportada para instalación on‑prem de Redis Enterprise en esa fecha.

| Plataforma | Redis Enterprise Software (instalación en SO) | Notas |
|------------|-----------------------------------------------|--------|
| **RHEL 9** | ✅ (desde Redis Software **7.4.2**, según [Supported platforms](https://redis.io/docs/latest/operate/rs/references/supported-platforms/)) | Opción para VMs/nodos dedicados solo a Redis. |
| **RHEL 10** | ❌ No listado (mayo 2026) | No planificar RPM/instalador Enterprise directo sobre RHEL 10 sin confirmación comercial y nueva matriz Redis. |
| **OpenShift + Redis Operator** | ✅ Validar **versión OCP + versión operador** | Redis corre en contenedores; desacopla RHEL 10 del host ACE de la capa Redis Enterprise. Ver [manual OpenShift](docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md). |
| **Redis OSS en RHEL 10** | ✅ vía **Remi** (p. ej. Redis 7.2.14) | PoC/laboratorio; no equivale al soporte Redis Enterprise. Guía: [`INSTALACION-REDIS-OSS-RHEL10.md`](docs/INSTALACION-REDIS-OSS-RHEL10.md). |

**Implicación para la PoC con Banrural:**

1. **ACE en RHEL 10** puede consumir Redis por red (host/puerto/TLS) aunque Redis no se instale en ese mismo SO.  
2. Si el requisito es **Redis Enterprise con soporte**, priorizar **OpenShift (Operator)** o **servidores RHEL 9** para Redis, no instalación Enterprise nativa en RHEL 10.  
3. Antes del despliegue, ejecutar checklist: versión RHEL/OCP, channel del operador, imágenes del CSV y conectividad desde Integration Server → Redis.

---

## ACE 12 y Redis: qué debes saber

| Tema | ACE 12.x |
|------|-----------|
| **Nodo Redis de IBM** | **No incluido.** El **Redis Request node** existe a partir de **ACE 13.0.5**. En ACE 12 la integración directa se implementa con **JavaCompute** + cliente Java (p. ej. **Jedis**), o con un servicio intermedio (HTTP). |
| **IBM App Connect (Designer)** | El conector Redis descrito en [How to use IBM App Connect with Redis](https://www.ibm.com/docs/en/app-connect/12.0.x?topic=hga-redis-1) aplica a flujos en el ecosistema **App Connect** (catálogo, Designer), no sustituye el patrón Java en **ACE Toolkit**; sirve como referencia de **operaciones y buenas prácticas** (strings, hashes, TTL, conexión). |
| **Evolución** | Si migras a **ACE ≥ 13.0.5**, valora sustituir el código Java por el nodo Redis mantenido por IBM; el diseño de **claves y TTL** de esta guía sigue siendo válido. |

---

## Objetivo de la PoC

- Demostrar lecturas/escrituras en **memoria** con baja latencia frente a lecturas repetidas a la **BD**.
- Comparar con el modo actual mediante **métricas** acordadas (latencias, carga en BD, hit ratio).
- Definir un patrón **reutilizable** (claves, políticas, JARs compartidos) para extender Redis a más flujos ACE 12.

---

## Parte 1 — Instalar Redis en Linux

> **RHEL 10:** Redis Enterprise no aplica on‑prem; para **Redis OSS** sigue [`docs/INSTALACION-REDIS-OSS-RHEL10.md`](docs/INSTALACION-REDIS-OSS-RHEL10.md). Para Enterprise, OpenShift: [`docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md`](docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md). Las secciones genéricas siguientes aplican a otras distros o referencia rápida.

### 1.1 Ubuntu / Debian (paquete del sistema)

```bash
sudo apt update
sudo apt install -y redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
sudo systemctl status redis-server --no-pager
```

Comprobación básica:

```bash
redis-cli ping
# Esperado: PONG
```

### 1.2 RHEL 10 — Redis OSS (Remi)

**Guía completa validada:** [`docs/INSTALACION-REDIS-OSS-RHEL10.md`](docs/INSTALACION-REDIS-OSS-RHEL10.md).

**Sin Internet en el servidor:** usar el paquete [`packages/rhel10-x86_64/offline-redis-oss/`](packages/rhel10-x86_64/offline-redis-oss/) (RPMs + tarball + scripts).

Resumen (con repos):

```bash
sudo dnf install -y \
  https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
  https://rpms.remirepo.net/enterprise/remi-release-10.rpm
sudo crb enable
sudo dnf module enable redis:remi-7.2 -y
sudo dnf install -y redis
sudo systemctl enable --now redis
```

### 1.3 RHEL 8/9 / Rocky / Alma (AppStream)

**Redis OSS** vía repos de la distro. **Redis Enterprise** on‑prem: solo RHEL 8/9 según [matriz Redis](https://redis.io/docs/latest/operate/rs/references/supported-platforms/).

```bash
sudo dnf install -y redis
sudo systemctl enable --now redis
redis-cli ping
```

### 1.4 Configuración mínima recomendada para laboratorio

Edita el fichero de configuración (ruta típica: `/etc/redis/redis.conf` o `/etc/redis.conf`):

| Parámetro | Uso en PoC |
|-----------|------------|
| `bind` | En laboratorio: `127.0.0.1` o IP del servidor; en red, restringe a subredes necesarias. |
| `requirepass` | Contraseña si ACE se conecta por red. |
| `protected-mode yes` | Mantener salvo que acotes red y riesgos. |
| `maxmemory` + `maxmemory-policy` | Para caché: p. ej. `allkeys-lru`. |

Tras cambios:

```bash
sudo systemctl restart redis-server   # o redis, según distro
```

### 1.5 Firewall (si aplica)

Abre solo el puerto que uses (por defecto **6379**) hacia los hosts de los **Integration Servers** ACE.

### 1.6 TLS (producción)

Si Redis expone TLS, alinea certificados y validación con la política de tu organización. La guía de conexión del ecosistema IBM (host, puerto, contraseña, base, certificados) está en [Connecting to Redis](https://www.ibm.com/docs/en/app-connect/12.0.x?topic=hga-redis-1).

---

## Parte 2 — ACE 12: caché en el flujo (resumen)

El detalle operativo está en el [**manual completo ACE 12**](docs/MANUAL-CACHE-REDIS-ACE12.md). Resumen:

1. **Patrón cache-aside:** intento **GET** en Redis → si **hit**, respuesta sin BD → si **miss**, consulta **BD**, luego **SETEX** con **TTL**.
2. **Implementación en ACE 12:** dos **JavaCompute** (lectura con terminal adicional **`miss`**, escritura tras la BD), **Jedis** + **Commons Pool2**, propiedades del nodo o **User-defined policy** ([políticas desde JavaCompute](https://www.ibm.com/docs/en/app-connect-enterprise/12.0.x?topic=java-accessing-user-defined-policy-from-javacompute-node)).
3. **Claves:** prefijo estable `ace:<aplicacion>:<recurso>:<id>` y **TTL** documentado.

---

## Parte 3 — Cómo medir el beneficio frente al modo actual (solo BD)

Define antes qué es “éxito” (p. ej. bajar **p95** un X % o reducir lecturas a la BD un Y % en un caso de uso concreto).

### 3.1 Métricas técnicas comparables

| Métrica | Modo actual (BD) | Modo con Redis |
|--------|-------------------|----------------|
| Latencia **p50 / p95 / p99** extremo a extremo | Baseline | Con caché |
| **Consultas/s** a la BD | Baseline | Debe bajar en lecturas cacheables |
| **CPU / I/O** en el servidor de BD | Baseline | Suele reducirse |
| **Hit ratio** | N/A | hits / (hits + misses) |

Instrumentación: registro en ACE, APM o logs estructurados; en Redis: `INFO stats`, `used_memory`, comandos/s.

### 3.2 Informe mínimo de la PoC

1. Caso de uso y clave + TTL.  
2. Tabla baseline vs Redis (misma carga y duración).  
3. Hit ratio y notas de **consistencia** (invalidación / stale).

---

## Parte 4 — Escalar a todos los flujos ACE 12 de forma eficiente

- **Mismos JARs** (Jedis, pool) en un estándar de despliegue compartido; evita versiones divergentes por BAR.  
- **User-defined policies** o propiedades por **entorno** (DEV/TEST/PROD), no credenciales en código.  
- **Catálogo de claves** y límites de `maxmemory` / eviction acordados con operaciones.  
- **Un Redis** (o cluster) compartido con **prefijos** por aplicación; HA con réplicas/Sentinel/Cluster según SLA.  
- **Pool de conexiones** en JVM (no abrir/cerrar conexión por mensaje); timeouts y **failure** del flujo definidos para caída de Redis.  
- Si conviven **App Connect Designer** y **ACE**, un mismo Redis es posible con convenciones de claves comunes; ver [How to use IBM App Connect with Redis](https://www.ibm.com/docs/en/app-connect/12.0.x?topic=hga-redis-1).

---

## Referencias

- **Manual ACE 12:** [docs/MANUAL-CACHE-REDIS-ACE12.md](docs/MANUAL-CACHE-REDIS-ACE12.md)  
- **Redis OSS RHEL 10:** [docs/INSTALACION-REDIS-OSS-RHEL10.md](docs/INSTALACION-REDIS-OSS-RHEL10.md)  
- **Paquete offline RHEL 10:** [packages/rhel10-x86_64/offline-redis-oss/](packages/rhel10-x86_64/offline-redis-oss/)  
- **OpenShift + Redis Operator:** [docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md](docs/DESPLIEGUE-REDIS-OPENSHIFT-OPERATOR.md)  
- Redis Enterprise — [Supported platforms](https://redis.io/docs/latest/operate/rs/references/supported-platforms/)  
- Redis Enterprise for Kubernetes — [Supported Kubernetes distributions](https://redis.io/docs/latest/operate/kubernetes/reference/supported_k8s_distributions/)  
- IBM — *How to use IBM App Connect with Redis*: https://www.ibm.com/docs/en/app-connect/12.0.x?topic=hga-redis-1  
- IBM ACE 12 — *Accessing a user-defined policy from a JavaCompute node*: https://www.ibm.com/docs/en/app-connect-enterprise/12.0.x?topic=java-accessing-user-defined-policy-from-javacompute-node  
- Redis: https://redis.io/docs/

---

## Contenido futuro sugerido

- Plantilla de resultados de PoC (tablas baseline vs Redis).  
- Ejemplo BAR de laboratorio sin datos sensibles (si la licencia y la política interna lo permiten).
