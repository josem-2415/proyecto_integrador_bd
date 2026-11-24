# S20. Solución de referencia de la parte A (uso del profesor)

SQL probado en PostgreSQL 16 sobre el esquema de [`S20-rendimiento.sql`](S20-rendimiento.sql), recién cargado (`SET search_path TO rendimiento;`). Los tiempos son los de un computador portátil con el contenedor del curso; en otros equipos cambian, pero los órdenes de magnitud y las proporciones deberían mantenerse.

| Consulta | Sin índices | Con índices (A2) | Desnormalizada |
|---|---|---|---|
| Catálogo (`Libro 12%`, 111 títulos) | ~16 ms | ~2 ms | ~0,3 ms (columna `disponibles`) |
| Top 20 más prestados | ~80 ms | (no aplica) | ~0,01 ms (vista materializada) |

El mensaje para la puesta en común: **el índice da casi toda la mejora del catálogo sin agregar redundancia**. La columna desnormalizada gana otro orden de magnitud, pero sobre 2 ms, que nadie nota en una búsqueda. En cambio, el top 20 no se arregla con un índice (tiene que recorrer los 300 000 préstamos para contarlos), y ahí la vista materializada sí se justifica.

## A1. La consulta del catálogo

(a) `LEFT JOIN` para que los ejemplares sin préstamo abierto se conserven, y `count(p.id)` para que cuenten 0 (con `count(*)` cada ejemplar sin préstamo contaría 1 y todos los libros saldrían con 0 disponibles).

(c) El nodo costoso es `Seq Scan on prestamo p` con `Filter: (fecha_devolucion IS NULL)` y `Rows Removed by Filter: 300000`: recorre todos los préstamos para quedarse con los 3 750 abiertos. Se lleva unos 13 de los 16 ms.

## A2. Índices

```sql
CREATE INDEX ejemplar_isbn_idx    ON ejemplar (isbn);
CREATE INDEX prestamo_abierto_idx ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;
```

El `Seq Scan on prestamo` se convierte en `Index Scan using prestamo_abierto_idx` dentro de un `Nested Loop Left Join`: por cada ejemplar (333) busca en el índice su préstamo abierto. No se agregó ninguna redundancia al modelo. Con solo 5 000 títulos el planificador puede seguir usando `Seq Scan` sobre `ejemplar` (es pequeña); está bien.

Variante aceptable: un índice normal sobre `prestamo (id_ejemplar)` también mejora, aunque es más grande (indexa los 303 750 préstamos, no los 3 750 abiertos).

## A3. Desnormalizar `disponibles`

```sql
ALTER TABLE libro ADD COLUMN disponibles smallint;

UPDATE libro l
SET    disponibles =
         (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
       - (SELECT count(*) FROM prestamo p JOIN ejemplar e ON e.id_ejemplar = p.id_ejemplar
          WHERE  e.isbn = l.isbn AND p.fecha_devolucion IS NULL);          -- UPDATE 5000

ALTER TABLE libro ALTER COLUMN disponibles SET NOT NULL,
                  ADD CHECK (disponibles >= 0);

SELECT disponibles, count(*) FROM libro GROUP BY 1;    -- 2: 3750, 3: 1250
```

**Predicción:** entre tres números consecutivos (3i-2, 3i-1, 3i) hay a lo sumo un múltiplo de 4. Hay 3 750 ejemplares múltiplos de 4, cada uno en un libro distinto, así que 3 750 libros tienen un préstamo abierto (2 disponibles) y los otros 1 250 tienen 3.

Si el grupo agrega la columna con `NOT NULL` antes del `UPDATE`, el `ALTER` falla (hay filas): es parte del ejercicio. También es válido `ADD COLUMN disponibles smallint NOT NULL DEFAULT 0` y luego el `UPDATE`.

(b)

```sql
SELECT isbn, titulo, disponibles FROM libro WHERE titulo LIKE 'Libro 12%';   -- ~0,3 ms
```

(c)

```sql
CREATE VIEW descuadre AS
SELECT   l.isbn, l.disponibles AS guardado, count(e.id_ejemplar) - count(p.id) AS calculado
FROM     libro l
JOIN     ejemplar e    ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar AND p.fecha_devolucion IS NULL
GROUP BY l.isbn, l.disponibles
HAVING   l.disponibles <> count(e.id_ejemplar) - count(p.id);

-- después del INSERT del préstamo 400001 (ejemplar 1, del Libro 1)
SELECT * FROM descuadre;     -- 9780000000001 | 3 | 2
```

(d) La respuesta esperada es un trigger sobre `prestamo` (insertar un préstamo abierto resta 1; registrar la devolución suma 1), que es candidato natural al Hito 4. "La aplicación lo actualiza en la misma transacción" es aceptable si el grupo reconoce el riesgo (un `INSERT` desde `psql` o una carga masiva se lo salta) y deja `descuadre` como verificación. Una vista materializada no sirve aquí: el catálogo tiene que estar al día al prestar.

## A4. Top 20 con vista materializada

```sql
CREATE MATERIALIZED VIEW top_prestados AS
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;                    -- SELECT 20

SELECT * FROM top_prestados;                       -- ~0,01 ms; Libro 1 (3881), Libro 2 (1881), Libro 3 (1401)…
```

(c) Después de los 4 000 préstamos del ejemplar 15 000 (Libro 5000, que tenía 21), `top_prestados` sigue mostrando a Libro 1 de primero; la consulta directa ya muestra a Libro 5000 con 4 021. Después del `REFRESH`, Libro 5000 aparece de primero.

(d) Cualquier respuesta argumentada. Lo razonable para un reporte de "más prestados" es refrescar una vez al día (de noche) o al abrir el reporte si es poco usado; nadie decide nada por un préstamo de diferencia. Quién lo hace: un trabajo programado (fuera del alcance del curso), la API antes de servir el reporte, o el bibliotecario con un botón "actualizar". Lo que no se acepta: refrescarla después de cada préstamo (cuesta lo mismo que la consulta original, y entonces no se ganó nada).

## A5. ¿Derivado o histórico?

- **Si el plazo nunca cambia** y no hay excepciones, `fecha_esperada = fecha_prestamo + 14` siempre: es un dato derivado y guardarlo es redundancia (podría ser una columna generada o calcularse en la consulta).
- **Si el plazo puede cambiar** (la biblioteca pasa a 21 días) o hay plazos especiales (libros de referencia, renovaciones), la fecha esperada de cada préstamo es un **hecho histórico** del préstamo: depende de `id` del préstamo, no de una regla actual. Guardarla es correcto en 3FN. Calcularla con la regla nueva cambiaría las fechas de los préstamos viejos y haría aparecer o desaparecer moras.

En el proyecto, las reglas por defecto (sección 3.2) dicen que cada equipo puede ajustar el plazo: la segunda lectura es la que conviene, y la mayoría de esquemas ya guarda `fecha_esperada`. Grupos que guardan solo `fecha_prestamo` y calculan `+ 14` en los reportes (como permitía S15, sección 8.5) deberían documentar ese supuesto en el Hito 3.

## Parte B: qué revisar en el Hito 3

- Que las dependencias del documento estén **escritas con su regla**, no solo listadas. Es el criterio "análisis de formas normales" de la rúbrica del proyecto.
- Que `postgres/init/` cree el esquema **nuevo**: el error más común es migrar la base del grupo con `normalizacion.sql` y dejar el script de `init/` con el esquema viejo (criterio "esquema actualizado y consistente").
- Que una desnormalización venga con su mecanismo **y** su consulta de verificación. "Guardamos `ejemplares_disponibles` por rendimiento" sin medición ni mecanismo es un 1 en el segundo criterio, no un 2.
- Que los reportes de S16 sigan dando los resultados esperados con `datos-prueba.sql`.
