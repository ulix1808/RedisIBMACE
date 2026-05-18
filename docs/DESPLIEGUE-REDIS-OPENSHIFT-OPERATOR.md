# Despliegue de Redis Enterprise en OpenShift con el Redis Operator

Guía para desplegar **Redis Enterprise for Kubernetes** en **Red Hat OpenShift** mediante el **Redis Enterprise Operator** (OperatorHub / OLM). Pensada para entornos donde los nodos o VMs usan **RHEL 10** y **no** es viable instalar **Redis Enterprise Software** directamente sobre el SO (véase validación en el [`README.md`](../README.md)).

> **Fecha de referencia:** 15 de mayo de 2026. Antes de producción, confirma versiones en [Supported Kubernetes distributions](https://redis.io/docs/latest/operate/kubernetes/reference/supported_k8s_distributions/) y [release notes del operador](https://redis.io/docs/latest/operate/kubernetes/release-notes/).

---

## 1. Por qué OpenShift en este escenario

| Enfoque | Situación típica |
|---------|------------------|
| **Redis Enterprise en RHEL 9 (VM/bare metal)** | Soportado por Redis para instalación “on box” ([plataformas soportadas](https://redis.io/docs/latest/operate/rs/references/supported-platforms/)). |
| **RHEL 10 en el cliente** | **No** aparece en la matriz oficial de Redis Enterprise Software (mayo 2026). |
| **Redis Enterprise en OpenShift (Operator)** | Redis valida **versión de OpenShift + versión del operador**; el runtime va en **contenedores** certificados, no como paquete RPM sobre RHEL 10 del host ACE. |

Para la PoC con **IBM ACE 12**, ACE puede consumir Redis publicado en el cluster (Service/Route) con host, puerto, contraseña y TLS alineados con el manual de caché [`MANUAL-CACHE-REDIS-ACE12.md`](MANUAL-CACHE-REDIS-ACE12.md).

---

## 2. Alineación de versiones (obligatorio antes de instalar)

No mezcles canal del operador, imagen del cluster Redis (REC) y versión de OpenShift sin revisar la matriz oficial.

### 2.1 OpenShift ↔ Redis Operator (referencia marzo–mayo 2026)

Ejemplos tomados de la documentación Redis ([Supported Kubernetes distributions](https://redis.io/docs/latest/operate/kubernetes/reference/supported_k8s_distributions/)):

| Versión operador Redis (ejemplo) | OpenShift Container Platform (ejemplos) |
|----------------------------------|----------------------------------------|
| **8.0.18-11** (mar 2026) | 4.21 ✅, 4.20 ✅, 4.19 ✅, 4.18 ⚠️ |
| **8.0.10-21** (ene 2026) | 4.20 ✅, 4.19 ✅, 4.18 ✅, 4.17 ⚠️ |
| **7.22.0-15** (jul 2025) | 4.19 ✅, 4.18 ✅, 4.17 ⚠️ |

- ✅ = probado/soportado para esa combinación.  
- ⚠️ = soporte con advertencias; revisar release notes.  
- ❌ = no usar esa combinación.

**Acción:** anota la versión exacta de tu cluster (`oc version`) y elige el **channel** del operador en OperatorHub que coincida con una fila ✅ de la matriz.

### 2.2 Imágenes (OperatorHub certificado en OpenShift)

Con la instalación **Certified** desde OperatorHub, las imágenes suelen resolverse desde el **registry de Red Hat** (no hace falta hardcodear tags en la PoC si usas el bundle OLM aprobado).

Para instalaciones avanzadas o air-gapped, Redis publica tags explícitos en release notes; ejemplo de familia **8.0.16-24** (mar 2026, referencia):

| Componente | Imagen de referencia (upstream / documentación) |
|------------|--------------------------------------------------|
| Redis Enterprise (nodo) | `redislabs/redis:8.0.16-64` |
| Operador | `redislabs/operator:8.0.16-24` |
| Controller / rigger | `redislabs/k8s-controller:8.0.16-24` |

En **OpenShift**, el operador certificado puede usar variantes empaquetadas para OLM (p. ej. bundle `8.0.16-24.4`). **Usa las imágenes que indique el CSV/Subscription instalado**, no mezcles tags de otra versión del operador.

### 2.3 Redis OSS vs Redis Enterprise en OpenShift

| Producto | Operador / instalación | Uso en esta PoC |
|----------|------------------------|----------------|
| **Redis Enterprise** | Redis Enterprise Operator (este documento) | Caché gestionada, REC/REDB, soporte corporativo, alineado con IBM App Connect (Redis 6.x–7.x en documentación IBM). |
| **Redis OSS** | Operadores comunitarios u otros charts | Válido para laboratorio; no sustituye matrices de soporte de Redis Enterprise. |

---

## 3. Prerrequisitos en el cluster

- OpenShift **4.x** con versión **compatible** con el channel del operador elegido (sección 2.1).  
- Permisos de **cluster-admin** o equivalentes para instalar operadores y SCC.  
- Namespace dedicado (p. ej. `redis-enterprise`).  
- **StorageClass** por defecto o explícita para volúmenes del REC (PersistentVolumeClaims).  
- Recursos de nodo suficientes para el tamaño de la PoC (CPU/memoria según [planificación REC](https://redis.io/docs/latest/operate/kubernetes/re-clusters/)).  
- Límites de **file descriptors** ≥ 100.000 en workers, o habilitar [allow automatic resource adjustment](https://redis.io/docs/latest/operate/kubernetes/security/allow-resource-adjustment) según documentación Redis.  
- Salida de red desde los **Integration Servers ACE** hacia el Service/Route de Redis (puerto **6379** o TLS según configuración).

Comprobaciones útiles:

```bash
oc version
oc get nodes
oc get storageclass
```

---

## 4. Instalar el Redis Enterprise Operator (OperatorHub)

Procedimiento alineado con [Deploy Redis Enterprise with OpenShift OperatorHub](https://redis.io/docs/latest/operate/kubernetes/deployment/openshift/openshift-operatorhub/):

1. Consola OpenShift → **Operators → OperatorHub**.  
2. Buscar **Redis Enterprise Operator provided by Redis** (sello **Certified**).  
3. **Install Operator**:  
   - **Namespace:** dedicado (p. ej. `redis-enterprise`). Solo un namespace por instalación de operador.  
   - **Channel:** versión alineada con tu OCP (sección 2.1).  
   - **Approval strategy:** **Manual** en entornos controlados (PROD/PRE).  
4. Aprobar el **InstallPlan** y verificar en **Operators → Installed Operators** que el operador está `Succeeded`.  
5. **No modificar ni borrar** el StatefulSet que crea el operador durante el despliegue del REC; puede destruir el cluster.

### 4.1 Security Context Constraints (SCC)

- Versiones del operador **≥ 7.22.0-6** suelen ejecutarse **sin** permisos para ajuste automático de recursos del nodo.  
- Si migras desde releases antiguos, revisa SCC `redis-enterprise-scc-v2` y enlaces al service account del REC según la guía oficial.  
- Operador **≤ 6.2.18-41:** instalar la SCC de seguridad **antes** del operador (ver enlace en documentación Redis OpenShift).

---

## 5. Crear el cluster Redis (REC) y la base (REDB)

Desde **Installed Operators → Redis Enterprise Operator → Operator details**:

APIs expuestas: **RedisEnterpriseCluster (REC)** y **RedisEnterpriseDatabase (REDB)**.

### 5.1 Ejemplo mínimo REC (YAML orientativo)

Ajusta `nodes`, `storageClassName`, `memory` y `cpu` al tamaño de la PoC. El nombre del REC **no puede cambiarse** después de la creación.

```yaml
apiVersion: app.redislabs.com/v1
kind: RedisEnterpriseCluster
metadata:
  name: rec-poc
  namespace: redis-enterprise
spec:
  nodes: 3
  redisEnterpriseNodeResources:
    limits:
      cpu: "2"
      memory: 4Gi
    requests:
      cpu: "1"
      memory: 4Gi
  persistentSpec:
    enabled: true
    storageClassName: gp3   # sustituir por la StorageClass del cluster
    volumeSize: "20Gi"
```

Aplicar:

```bash
oc apply -f rec-poc.yaml
oc get rec -n redis-enterprise
oc get pods -n redis-enterprise
```

Esperar que el REC esté en estado **Running** / **Valid** según muestre `oc describe rec rec-poc -n redis-enterprise`.

### 5.2 Ejemplo mínimo REDB (base para caché)

```yaml
apiVersion: app.redislabs.com/v1
kind: RedisEnterpriseDatabase
metadata:
  name: cache-poc
  namespace: redis-enterprise
spec:
  redisEnterpriseCluster:
    name: rec-poc
  memorySize: 1GB
  type: redis
  evictionPolicy: allkeys-lru
```

Tras crear el REDB, el operador expone credenciales y endpoints (secret + service). Obtén la contraseña y el host:

```bash
oc get redb cache-poc -n redis-enterprise -o yaml
oc get svc -n redis-enterprise
oc get secret -n redis-enterprise
```

Documenta para ACE: **hostname** (Service DNS interno o Route), **puerto**, **password**, **TLS** (si aplica).

---

## 6. Exponer Redis hacia ACE (fuera del cluster)

Opciones habituales:

| Método | Cuándo usarlo |
|--------|----------------|
| **Service ClusterIP** + acceso desde red del cluster | ACE corre en pods/workers con reachability al SDN de OpenShift. |
| **Route** (TLS passthrough o edge) | ACE en VMs RHEL fuera del cluster pero con ruta publicada/interna. |
| **Ingress / API gateway** | Políticas corporativas que centralizan salida. |

Para la PoC con ACE en **RHEL 10** on‑prem, suele usarse **Route interna** o **NodePort/LoadBalancer** acotado por firewall hacia los Integration Servers.

Comprobación desde una VM con `redis-cli` (si está permitido):

```bash
redis-cli -h <host> -p <port> -a '<password>' --tls  # si TLS
PING
```

---

## 7. Checklist de validación post-despliegue

- [ ] Versión OCP + channel operador verificadas en matriz Redis ✅  
- [ ] Operador `Installed` / `Succeeded`  
- [ ] REC en estado saludable, PVCs enlazados  
- [ ] REDB creada, secreto de credenciales disponible  
- [ ] `PING` / `SET` / `GET` desde red de ACE  
- [ ] Parámetros documentados para JavaCompute (`redisHost`, `redisPort`, `redisPassword`, TLS)  
- [ ] TTL y prefijos de clave acordados (`ace:...`) según manual ACE  

---

## 8. Operación y actualizaciones

- Actualizaciones del operador: estrategia **Manual** en OperatorHub; leer [release notes](https://redis.io/docs/latest/operate/kubernetes/release-notes/) antes de aprobar un nuevo InstallPlan.  
- Copias de seguridad y persistencia: definir política sobre PVCs del REC para entornos no laboratorio.  
- Monitoreo: métricas del operador/REC y `INFO` de Redis para hit ratio y memoria en la PoC.

---

## 9. Relación con RHEL 10 del cliente

- **ACE / aplicaciones en RHEL 10:** compatibles con conectarse a Redis **remoto** (OpenShift o RHEL 9).  
- **Redis Enterprise como RPM en RHEL 10:** no validado en la matriz oficial a mayo 2026; no usar para PoC corporativa con soporte Redis Enterprise sin excepción escrita.  
- **Ruta recomendada con RHEL 10 + requisito Enterprise:** Redis Enterprise Operator en OpenShift **o** nodos dedicados **RHEL 9** solo para Redis.

---

## Referencias

- [Deploy Redis Enterprise with OpenShift OperatorHub](https://redis.io/docs/latest/operate/kubernetes/deployment/openshift/openshift-operatorhub/)  
- [Supported Kubernetes distributions](https://redis.io/docs/latest/operate/kubernetes/reference/supported_k8s_distributions/)  
- [Redis Enterprise clusters (REC)](https://redis.io/docs/latest/operate/kubernetes/re-clusters/)  
- [Redis Enterprise databases (REDB)](https://redis.io/docs/latest/operate/kubernetes/re-databases/)  
- [Supported platforms — Redis Enterprise Software](https://redis.io/docs/latest/operate/rs/references/supported-platforms/)  
- Manual ACE 12 caché: [`MANUAL-CACHE-REDIS-ACE12.md`](MANUAL-CACHE-REDIS-ACE12.md)
