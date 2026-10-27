# Datos semilla del proyecto

CSV de ejemplo para el **Hito 2** (`../definicion-proyecto-final.md`, sección 8): la carga masiva de libros y lectores. Todos los equipos parten de estos mismos archivos; cada equipo puede ampliarlos con datos propios para sus pruebas y su demo de sustentación.

## Archivos

| Archivo | Filas | Para qué |
|---|---|---|
| `libros_semilla.csv` | 32 libros | Catálogo base, todos los datos válidos. Suficientes títulos para que el reporte "20 libros más prestados" tenga sentido (más de 20 para elegir entre ellos). |
| `lectores_semilla.csv` | 20 lectores | Usuarios lectores base, todos los datos válidos. |
| `libros_semilla_con_errores.csv` | 8 filas | **Deliberadamente con errores** — para probar la validación de la carga (Hito 2, criterio "Manejo de errores de carga"). No se espera que estas filas queden en el catálogo tal cual. |
| `lectores_semilla_con_errores.csv` | 6 filas | Igual que el anterior, para lectores. |

## Columnas

**`libros_semilla.csv`** — `isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles`
**`lectores_semilla.csv`** — `documento, nombres, apellidos, correo, telefono`

Estas columnas son un punto de partida razonable, no un esquema obligatorio — cada equipo decide cómo se traducen a su propio modelo de datos (Hito 1). Si el modelo de un equipo necesita columnas adicionales (ej. editorial, dirección del lector), puede ampliar el CSV; lo que se evalúa en el Hito 2 es que la carga funcione y valide errores razonables, no que el CSV tenga una forma específica.

**Nota — contraseñas de login:** estos archivos no incluyen contraseña para los lectores a propósito (no es buena práctica distribuir contraseñas en texto plano, ni siquiera de prueba, en un archivo versionado). Cómo se provisiona la contraseña inicial de un lector cargado por CSV (ej. un valor por defecto que se le pide cambiar, el número de documento como clave inicial, etc.) es una decisión de diseño del equipo — recuerden que igual debe quedar guardada con hash en la base de datos (sección 6.2 del documento de proyecto).

## Qué prueba cada fila de los archivos "con_errores"

**`libros_semilla_con_errores.csv`:**

| Fila (por `isbn`) | Problema |
|---|---|
| `9780000000001` | ISBN duplicado (ya existe en `libros_semilla.csv`) |
| `9780000000033` | `titulo` vacío |
| `9780000000034` | `ejemplares_disponibles` no numérico (`"dos"`) |
| `9780000000035` | `anio_publicacion` no numérico (`"MCMXLIX"`) |
| `9780000000036` | Fila con una columna de más (desalineada) |
| `9780000000037` | `autor` vacío |
| *(vacío)* | `isbn` vacío |
| `9780000000038` | `ejemplares_disponibles` negativo (`-3`) — numéricamente válido pero sin sentido de negocio |

**`lectores_semilla_con_errores.csv`:**

| Fila (por `documento`) | Problema |
|---|---|
| `1000000001` | `documento` duplicado (ya existe en `lectores_semilla.csv`) |
| `1000000021` | `correo` vacío |
| `1000000022` | `correo` mal formado (sin `@`) |
| `1000000023` | `telefono` no numérico |
| *(vacío)* | `documento` vacío |
| `1000000025` | `nombres` vacío |

No hay una única "respuesta correcta" sobre qué hacer con cada fila (rechazarla, corregirla, cargarla con una advertencia) — lo que se evalúa es que el equipo tenga **algún** criterio consistente y lo aplique, no que adivine el que tenían en mente los autores del CSV.
