# Sistema de Gestión Bibliotecaria
**Proyecto Final · Base de Datos Relacional**  
**Curso:** Bases de Datos (Cuarto Semestre)  
**Integrantes:**
- Andres Felipe Rengifo Rodriguez - 202519613
- Jose Manuel Cardona Gil - 202521653
- Juan Camilo Morales - 202515391
- Jorge Luis Castro - 202517065


---

## 1. Descripción del Entorno

El proyecto se ejecuta en contenedores mediante **Docker Compose**, integrando el motor relacional, la administración visual y el entorno de aplicación:

| Servicio | Imagen | Función en el Proyecto | Puerto Local |
|---|---|---|---|
| `postgres` | `postgres:16` | Motor de base de datos relacional (esquema `biblioteca`) | `localhost:5432` |
| `pgadmin` | `dpage/pgadmin4:8` | Interfaz web gráfica de administración | `localhost:5050` |
| `node` | `node:20-alpine` | Entorno para la API / Backend del proyecto | `localhost:3000` |

---

## 2. Estructura del Repositorio

```text
taller-bd/
├── docker-compose.yml              # Definición de servicios (Postgres, pgAdmin, Node)
├── .env.example                    # Plantilla de variables de entorno
├── README.md                       # Documentación principal y bitácora de entregas
├── docs/
│   └── mapeo-y-criterios.md        # Mapeo CSV -> esquema y criterios de error
├── assets/                         # Capturas de comprobación de las ejecuciones
├── postgres/
│   ├── init/
│   │   └── 01_esquema.sql          # Esquema de arranque automático (7 tablas)
│   ├── scripts/
│   │   ├── S14-carga-libros.sql    # Script de carga masiva de libros
│   │   ├── S14-carga-lectores.sql  # Script de carga masiva de lectores
│   │   ├── correr-pruebas.sh       # Script de ejecución automatizada
│   │   └── datos/                  # Archivos CSV (semilla y propios)
│   └── data/                       # Datos persistentes de Postgres (ignorado en git)
├── pgadmin/
│   └── servers.json                # Conexión precargada a Postgres
└── node/
    ├── docker-entrypoint.sh
    └── proyecto/                   # Código de la aplicación
```

---

## 3. Puesta en Marcha (Comandos Rápidos)

Requisitos: **Docker Desktop** encendido.

```bash
# 1. Levantar la base de datos en segundo plano
docker compose up -d postgres

# 2. Conectarse a la consola psql
docker compose exec postgres psql -U curso -d curso

# 3. Levantar también la interfaz visual pgAdmin (opcional)
docker compose up -d pgadmin
# (Acceder en el navegador a http://localhost:5050 - credenciales: estudiante@curso.edu.co / curso)

# 4. Apagar los contenedores (los datos se conservan)
docker compose down
```

### Reiniciar la base de datos desde cero
Si se modifica `01_esquema.sql` y se requiere regenerar la base limpia:
```bash
docker compose down
# En Windows (PowerShell):
Remove-Item -Recurse -Force postgres/data/*
# En Linux / Mac:
rm -rf postgres/data/*

docker compose up -d postgres
```

---

## 4. Bitácora de Entrega · Hito 2 (Sesión 14)

### A. Ubicación de Archivos de la Entrega

- **Esquema de arranque (7 tablas):** [`postgres/init/01_esquema.sql`](postgres/init/01_esquema.sql)
- **Scripts de carga:** [`postgres/scripts/S14-carga-libros.sql`](postgres/scripts/S14-carga-libros.sql) y [`postgres/scripts/S14-carga-lectores.sql`](postgres/scripts/S14-carga-lectores.sql)
- **CSV propio:** [`postgres/scripts/datos/libros_propio.csv`](postgres/scripts/datos/libros_propio.csv)
- **Mapeo y criterios de error:** Se encuentran en la carpeta `docs/` en el archivo [`docs/mapeo-y-criterios.md`](docs/mapeo-y-criterios.md)
- **Capturas de comprobación:** Todas las imágenes se encuentran almacenadas en la carpeta `assets/`

---

### B. Cargas Ejecutadas y Comprobaciones


| Carga / Acción Realizada | Qué ocurrió en la ejecución | Imagen de Comprobación (en `assets/`) |
|---|---|---|
| **Creación del esquema** | Se crearon con éxito las 7 tablas del esquema `biblioteca`. | `Creacion_Tablas_Esquema_Biblioteca.png` |
| **Carga de libros limpio** | Se cargaron **32 libros** exitosamente con 0 rechazados usando `S14-carga-libros.sql`. | `Carga_Libros_Limpios.png` |
| **Carga de libros con errores** | Se rechazaron las **8 filas malas** por datos inválidos y entraron 0 a la tabla. | `Carga_Libros_Errores.png` |
| **Carga de lectores limpio** | Se cargaron **20 lectores** como usuarios exitosamente con 0 rechazados usando `S14-carga-lectores.sql`. | `Carga_Lectores_Limpios.png` |
| **Carga de lectores con errores** | Se rechazaron las **6 filas malas** (correo inválido, datos vacíos) y entraron 0 a la tabla. | `Carga_lectores_Errores.png` |
| **Carga de CSV propio** | Se cargaron **6 libros nuevos válidos** y se rechazaron **3 filas** con errores creados por el grupo. | `Carga_CSV_propio.png` |

---

### C. Prueba de la Última Línea de Defensa (Paso 5)

Se anuló deliberadamente la regla de validación de título vacío para forzar que el dato erróneo intentara insertarse en la tabla final:

- **Resultado:** La fila fue rechazada por la restricción `CHECK (titulo <> '')` de la tabla, provocando un **`ROLLBACK` automático** de toda la transacción. Ni los datos válidos ni los registros de rechazo se guardaron.
- **Comprobación:** La evidencia se encuentra en la imagen `Prueba_Ultima_Linea_De_Defensa.png` dentro de la carpeta `assets/`.

---

### D. Conteos Finales en Base de Datos

Verificación final consolidada mediante `psql`:

```sql
SELECT (SELECT count(*) FROM biblioteca.libro) AS libros,
       (SELECT count(*) FROM biblioteca.ejemplar) AS ejemplares,
       (SELECT count(*) FROM biblioteca.usuario) AS usuarios,
       (SELECT count(*) FROM biblioteca.rechazo_carga) AS rechazos;
```

- **38 Libros** (32 de semilla + 6 propios)
- **111 Ejemplares** (generados por cada copia de libro)
- **20 Usuarios (Lectores)**
- **49 Rechazos registrados** en `rechazo_carga`

**Comprobaciones en la carpeta `assets/`:**
- El conteo consolidado se encuentra en la imagen `Conteo_FInal.png`.
- La lista completa de rechazos auditados se encuentra en la imagen `Bitacora_Rechazados.png`.
