# 📦 XCP-ng VM Inventory v2

> Script de Bash mejorado para generar inventarios completos de VMs en pools XCP-ng / XenServer, con cabecera CSV dinámica, recolección en memoria y extracción precisa de IPs por interfaz.

Desarrollado por **Cristian Omar Jiménez Sánchez** · [@crisomarjs](https://github.com/crisomarjs)

---

## 📋 Descripción

Versión mejorada del script de inventario XCP-ng. Recopila todos los datos de las VMs en memoria antes de escribir el CSV, permitiendo generar una **cabecera dinámica** que se adapta automáticamente al número máximo de discos encontrado en el pool. Elimina el límite fijo de 4 discos de la versión anterior y mejora la precisión en la extracción de IPs correlacionándolas por dispositivo de red (`eth0`, `eth1`, etc.) en lugar de hacer una extracción genérica.

---

## ✅ Requisitos

| Requisito     | Detalle                                                  |
|---------------|----------------------------------------------------------|
| Sistema       | XCP-ng 8.x / XenServer 7.x o superior                   |
| Ejecución     | Directamente en el **Dom0** del hypervisor               |
| Permisos      | Root o usuario con acceso a `xe` CLI                     |
| Dependencias  | `xe`, `bash`, `date`, `awk`, `sed`, `grep` (incluidos en Dom0) |

> No requiere instalación de paquetes adicionales.

---

## 🚀 Uso

### 1. Copiar el script al Dom0

```bash
scp inventarios_xcp.sh root@<IP_DEL_HYPERVISOR>:/root/
```

### 2. Dar permisos de ejecución

```bash
chmod +x inventarios_xcp.sh
```

### 3. Ejecutar

```bash
bash inventarios_xcp.sh
```

El progreso se muestra en consola (stderr) y el CSV se escribe en el directorio actual al finalizar.

---

## 📂 Archivo de salida

```
inventario_<HYPERVISOR>_<POOL>_<FECHA>.csv
```

**Ejemplo:**

```
inventario_XCP-PROD-01_PoolDatacenter_2025-06-10.csv
```

---

## 📊 Columnas del CSV

La cabecera se genera **dinámicamente** según el máximo de discos detectado en el pool. Un pool donde la VM con más discos tenga 6, generará 6 columnas de disco.

| Columna             | Descripción                                                        |
|---------------------|--------------------------------------------------------------------|
| `VM Name`           | Nombre de la máquina virtual                                       |
| `VM Power State`    | Estado: `running`, `halted`, `suspended`                          |
| `Host Server`       | Host donde reside la VM (`N/A` si está apagada)                   |
| `CPU Count`         | vCPUs máximas asignadas (`VCPUs-max`)                             |
| `Memory (MB)`       | Memoria estática máxima en MB                                      |
| `Disk N (GB)`       | Tamaño de cada disco en GB — columnas generadas dinámicamente      |
| `Number of Disks`   | Total real de discos tipo `Disk` conectados                        |
| `OS Type`           | Nombre del SO reportado por XenTools (`os-version → name`)        |
| `Uptime`            | Tiempo encendida en formato `Xd Xh Xm` (solo VMs `running`)      |
| `MAC Addresses`     | MACs de todas las interfaces, separadas por `;`                    |
| `IP Addresses`      | IPs por interfaz correlacionadas por dispositivo (`eth0`, `eth1`) |

> **Nota:** `OS Type`, `IP Addresses` y `Uptime` requieren **XenServer Tools** instaladas y activas dentro de la VM. Sin ellas estos campos mostrarán `N/A`.

---

## 🆚 Diferencias con la versión anterior

| Aspecto                  | v1 (versión anterior)                        | v2 (este script)                              |
|--------------------------|----------------------------------------------|-----------------------------------------------|
| Límite de discos         | Fijo: máximo 4 columnas                      | Dinámico: tantas columnas como discos haya    |
| Escritura del CSV        | Línea a línea durante el procesamiento       | Todos los datos en memoria, CSV al finalizar  |
| Extracción de IPs        | Extracción genérica del bloque de networks   | Correlacionada por dispositivo (`eth0/ip`)    |
| Parsing de OS            | Campo `os-version` completo (verboso)        | Extrae solo el nombre (`name: ...`)           |
| Validación de entorno    | Ninguna                                      | Verifica presencia de `xe` antes de ejecutar  |
| Progreso en consola      | Sin indicador                                | Muestra `[N/total] VM` por cada VM procesada  |
| Limpieza de UUIDs        | Sin `xargs`                                  | `xargs` para eliminar espacios en UUIDs       |

---

## 📈 Salida de progreso en consola

```
==> Recopilando datos de 42 VMs...
  [1/42] SERVER-DB-01
  [2/42] SERVER-APP-01
  [3/42] SERVER-WEB-02
  ...
==> Máximo de discos detectado: 6. Generando CSV...
Inventario generado: inventario_XCP-PROD-01_PoolDatacenter_2025-06-10.csv
```

---

<p align="center">
  Desarrollado con ❤️ para equipos de infraestructura y virtualización
</p>
