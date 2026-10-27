# S4 — Laboratorio: primer contacto con PostgreSQL y MongoDB (Docker)

**Módulo 1, semana 2, sesión 4 · Laboratorio sincrónico (videollamada, salas por grupo de proyecto)**

## Objetivo

Que cada estudiante ejecute, en su propia máquina, un motor relacional (PostgreSQL) y uno documental (MongoDB) en paralelo, y compare — con datos reales frente a sus ojos, no solo en teoría — cómo se ve la misma información modelada en cada uno.

## Pre-laboratorio (trabajo independiente, antes de la sesión)

Esto **no se hace en las 2 horas de la sesión** — se asigna como parte de las 8 h/semana de trabajo independiente, para no perder el tiempo sincrónico en instalaciones:

1. Instalar [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) o Docker Engine + Docker Compose (Linux).
2. Verificar que `docker compose version` corre sin error en una terminal.
3. Descargar el archivo `docker-compose.yml` del repositorio del curso (ver sección "Materiales").

> 💡 **Nota:** no es necesario instalar ningún cliente de base de datos. Se usarán `psql` y `mongosh`, que ya vienen incluidos dentro de los contenedores de PostgreSQL y MongoDB respectivamente. Solo necesitan una terminal.

## Materiales

Archivo `docker-compose.yml` que se entrega a los estudiantes (o se sube al repositorio del curso):

```yaml
services:
  postgres:
    image: postgres:16
    container_name: postgres_curso
    environment:
      POSTGRES_USER: curso
      POSTGRES_PASSWORD: curso
      POSTGRES_DB: tienda
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  mongo:
    image: mongo:7
    container_name: mongo_curso
    environment:
      MONGO_INITDB_ROOT_USERNAME: curso
      MONGO_INITDB_ROOT_PASSWORD: curso
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db

volumes:
  postgres_data:
  mongo_data:
```

### Conexión a los motores desde la terminal

Una vez levantado el entorno con `docker compose up -d`, los estudiantes se conectan directamente a cada motor ejecutando un shell interactivo dentro del contenedor:

**PostgreSQL** — consola `psql`:

```bash
docker exec -it postgres_curso psql -U curso -d tienda
```

**MongoDB** — consola `mongosh`:

```bash
docker exec -it mongo_curso mongosh -u curso -p curso --authenticationDatabase admin
```

> 💡 Si usan Podman en lugar de Docker, reemplacen `docker` por `podman` en los comandos anteriores.

### Comandos básicos de referencia

| Acción | psql (PostgreSQL) | mongosh (MongoDB) |
|---|---|---|
| Listar bases de datos | `\l` | `show dbs` |
| Usar una base de datos | `\c tienda` | `use tienda` |
| Listar tablas/colecciones | `\dt` | `show collections` |
| Salir | `\q` | `exit` |

## Mecánica (2 horas)

1. **(15 min)** Levantar el entorno: `docker compose up -d`, verificar con `docker ps` que ambos contenedores están corriendo. Conectarse a PostgreSQL con `docker exec -it postgres_curso psql -U curso -d tienda` y a MongoDB con `docker exec -it mongo_curso mongosh -u curso -p curso --authenticationDatabase admin`. Verificar que ambas consolas responden.
2. **(35 min) En PostgreSQL:** crear una tabla `clientes` con columnas fijas (`id`, `nombre`, `ciudad`, `email`) e insertar 3 filas con `INSERT` (se da el SQL ya escrito — el objetivo de esta sesión no es aprender SQL a fondo, eso es M4; aquí solo se usa como vehículo de exploración). Ejecutar un `SELECT * FROM clientes`.
3. **(35 min) En MongoDB:** crear una colección `clientes` e insertar 3 documentos equivalentes, pero donde al menos uno tenga un campo que los otros no tienen (ej. un cliente con un array de `telefonos`, otro sin ese campo). Ejecutar una consulta `find()` equivalente al `SELECT` anterior.
4. **(20 min) Comparación guiada:** cada grupo responde, en su propio documento, 3 preguntas cortas (ver "Entregable").
5. **(15 min) Cierre:** 2–3 grupos comparten en voz alta una observación; el profesor conecta la actividad con el criterio de decisión de S2.

## Entregable

**Un documento por grupo** (no por estudiante) con:

1. Captura de pantalla de la consola `psql` mostrando el resultado de `SELECT * FROM clientes` con sus 3 filas.
2. Captura de pantalla de la consola `mongosh` mostrando el resultado de `db.clientes.find()` con sus 3 documentos (mostrando el campo que no todos tienen).
3. Respuesta corta (2–3 líneas cada una) a:
   - ¿Qué tuvieron que decidir de antemano en PostgreSQL que no tuvieron que decidir en MongoDB?
   - ¿Qué pasaría en cada motor si mañana un cliente necesita un campo nuevo que los demás no tienen?
   - Para el catálogo de productos del taller de S3 (escenario 1), ¿cuál de los dos usarían y por qué, ahora que lo probaron en la práctica?

## Rúbrica (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Ambos motores corriendo con datos** | Falta uno de los dos, o no hay evidencia (captura) | Ambos corren pero con datos incompletos/incorrectos | Ambos motores corriendo, con los datos pedidos y evidenciados en captura |
| **Consulta ejecutada en ambos** | No se muestra el resultado de la consulta en alguno de los dos | Se muestra en ambos pero de forma incompleta | `SELECT` y `find()` ejecutados y mostrados correctamente en ambos |
| **Calidad de la reflexión** | Respuestas genéricas o que no responden lo preguntado | Responde lo preguntado pero sin conectar con lo aprendido en S1/S2 | Respuestas conectan explícitamente con los conceptos de esquema fijo vs. flexible visto en la guía |

Máximo 6 puntos por grupo — checklist de 3 filas, revisión rápida incluso con ~20–26 entregas.
