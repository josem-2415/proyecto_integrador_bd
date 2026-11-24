# S22. Laboratorio: procedimientos, funciones y triggers (Hito 4)

**Módulo 6, semana 11, sesión 22 · Laboratorio sincrónico (videollamada, salas por grupo de proyecto) · *checkpoint Hito 4***

En S21 se construyeron, paso a paso y con la guía al lado, las funciones, procedimientos y triggers de una biblioteca pequeña. Este laboratorio pide hacer lo mismo **sin la receta**: en la **parte A**, en parejas, se programan las reglas de un sistema de reservas de salas de estudio, con una batería de pruebas que dice qué debe pasar y qué debe fallar. En la **parte B**, todo el grupo escribe el procedimiento y el trigger del proyecto y prepara la evidencia del Hito 4.

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Agregar restricciones `CHECK` de varias columnas y elegir la acción de cada FK de un esquema dado, justificando la elección.
- Escribir funciones en SQL que encapsulen una regla (horas reservadas, sala libre) y reutilizarlas desde un procedimiento y un trigger.
- Escribir un procedimiento que ejecute un caso de uso con varias validaciones y mensajes de error claros.
- Escribir un trigger `BEFORE` que impida saltarse una regla con un `INSERT` o `UPDATE` directo, y un trigger `AFTER` con `WHEN` que reaccione a un cambio de estado.
- Reescribir un ciclo fila por fila como una sola sentencia sobre el conjunto.
- Entregar al menos un procedimiento y un trigger con propósito real en el proyecto, con pruebas y evidencia de funcionamiento (Hito 4).

## Guía corta de pre-lectura (antes de la sesión)

### 1. El caso: salas de estudio

La biblioteca de la universidad presta cuatro salas de estudio por reserva. Las reglas, tal como las escribió la coordinación:

1. Una reserva dura como máximo **3 horas**, empieza y termina el mismo día, entre las **7:00 y las 21:00**.
2. Las personas que asisten no pueden superar la **capacidad** de la sala, y una sala **en mantenimiento** no se reserva.
3. Una sala no puede tener dos reservas **activas** que se crucen en el tiempo. Una reserva cancelada libera el horario.
4. Un estudiante reserva como máximo **6 horas por semana** (las canceladas no cuentan).
5. Un estudiante **sancionado** no puede reservar. Quien no se presenta a una reserva queda sancionado por **7 días**.
6. Una reserva se puede cancelar solo si está activa y todavía no ha empezado.

```
sala         (id_sala PK, nombre UNIQUE, capacidad, activa)
sala_recurso (id_sala FK → sala, recurso; PK de los dos)
estudiante   (codigo PK, nombre, correo UNIQUE, sancionado_hasta)
reserva      (id PK identidad, id_sala FK → sala, codigo FK → estudiante,
              inicio, fin, asistentes, estado: activa | cancelada | cumplida | no_asistio)
agenda       vista: las reservas con nombres de sala y estudiante, en orden
```

| id_sala | nombre | capacidad | activa |
|---|---|---|---|
| 1 | Sala A | 4 | sí |
| 2 | Sala B | 6 | sí |
| 3 | Sala C | 10 | sí |
| 4 | Sala D | 4 | **no** (mantenimiento) |

Elena (`2610005`) está sancionada por 30 días. La agenda de la **próxima semana** tiene 6 reservas (una cancelada); la de la **semana pasada** tiene 3, una de ellas todavía `activa` aunque ya pasó.

### 2. Fechas que no envejecen

Para que las pruebas den lo mismo cualquier día que se corran, el script trae la función `dia(n)`: el día `n` de la **próxima semana** (`dia(1)` es el lunes, `dia(5)` el viernes). Con números negativos se va hacia atrás: `dia(-13)` es el lunes de la semana pasada. Una fecha más una hora da un `timestamp`:

```sql
SELECT dia(1), dia(1) + time '08:00';   -- el próximo lunes, y ese lunes a las 8:00
```

### 3. Lo que hay que tener a mano

- La guía de S21 completa: las secciones 3 a 7 tienen la sintaxis de todo lo que se pide hoy.
- Para la parte B: el esquema del proyecto ya normalizado (Hito 3), con los datos de prueba de S16, y la decisión de S20 (parte B, punto 4) sobre qué dato desnormalizado había que mantener con un trigger.

**Pre-trabajo (15 min, antes de la sesión):**

1. Copiar el script [`S22-reservas.sql`](S22-reservas.sql) (publicado en el LMS) en `entorno-docker/postgres/scripts/` y ejecutarlo:

   ```bash
   docker compose exec postgres psql -U curso -d curso -f /scripts/S22-reservas.sql
   ```

2. `SET search_path TO reservas;` y `SELECT * FROM agenda;` para ver las reservas.
3. Crear un archivo `postgres/scripts/S22-grupo.sql` donde van a quedar, en orden, todas las sentencias de la parte A. Si algo sale mal, se corre otra vez `S22-reservas.sql` (borra todo lo creado) y luego `S22-grupo.sql`.

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor recuerda la estructura de una función de trigger (S21, sección 6.1) y la diferencia entre la regla en el procedimiento y la regla en el trigger (S21, secciones 5.4 y 6.2).
2. **(60 min) Parte A: reservas de salas.** En parejas, en orden (cada punto usa lo anterior). Cada punto trae su batería de pruebas: se corre y se compara con el resultado esperado.
3. **(45 min) Parte B: Hito 4 sobre el esquema propio.** Todo el grupo.
4. **(5 min) Cierre.** Cada grupo revisa la lista del checkpoint del Hito 4. El profesor recuerda que el Parcial 2 es en la próxima sesión (S23) e incluye M6.

### Parte A: reservas de salas

**A1. Restricciones y acciones referenciales (10 min).** (a) Agregar a `reserva` cuatro restricciones `CHECK` con nombre, para la regla 1 y para que `asistentes` sea positivo: `reserva_orden` (el fin es posterior al inicio), `reserva_duracion`, `reserva_horario` y `reserva_asistentes`. Pista: `fin - inicio` es un `interval`, `inicio::date` y `inicio::time` separan la fecha y la hora. (b) Decidir la acción `ON DELETE` de las tres FK (`sala_recurso → sala`, `reserva → sala`, `reserva → estudiante`), aplicarla con `ALTER TABLE … DROP CONSTRAINT … ADD CONSTRAINT …` y justificarla en una línea cada una. (c) Correr la batería:

```sql
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '09:00', 2);   -- debe fallar: reserva_orden
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '08:00', dia(4) + time '12:00', 2);   -- debe fallar: reserva_duracion
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '20:00', dia(4) + time '22:00', 2);   -- debe fallar: reserva_horario
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + time '10:00', dia(4) + time '11:00', 0);   -- debe fallar: reserva_asistentes

BEGIN;
DELETE FROM sala WHERE id_sala = 4;                  -- ¿qué pasa con sus recursos?
SELECT count(*) FROM sala_recurso WHERE id_sala = 4;
ROLLBACK;
DELETE FROM sala WHERE id_sala = 1;                  -- debe fallar: tiene reservas

BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(1) + time '09:00', dia(1) + time '10:00', 9);   -- ¿pasa?
ROLLBACK;
```

(d) El último `INSERT` pasa todas las restricciones. ¿Qué reglas de la sección 1 viola, y por qué ninguna restricción `CHECK` podría impedirlo?

**A2. Funciones (10 min).** Escribir en SQL (`LANGUAGE sql STABLE`):

- `horas_semana(p_codigo varchar, p_dia date) RETURNS numeric`: las horas que el estudiante tiene reservadas (sin contar las canceladas) en la semana del día dado, redondeadas a un decimal. Pista: `date_trunc('week', x)` da el lunes de la semana de `x`, y `extract(epoch FROM intervalo) / 3600` convierte un intervalo en horas.
- `sala_libre(p_sala integer, p_inicio timestamp, p_fin timestamp, p_excluir integer DEFAULT NULL) RETURNS boolean`: verdadero si la sala no tiene ninguna reserva **activa** que se cruce con ese intervalo, sin contar la reserva `p_excluir` (se necesita en A4). Dos intervalos `[a, b)` y `[c, d)` se cruzan si `a < d AND c < b`.

```sql
SELECT codigo, horas_semana(codigo, dia(1))   AS proxima,
               horas_semana(codigo, dia(-13)) AS pasada
FROM   estudiante ORDER BY codigo;
-- próxima: Ana 5.0, Bruno 2.0, Carla 3.0, Diego 2.0, Elena 0.0, Felipe 0.0
-- pasada:  Bruno 2.0, Carla 2.0, Felipe 2.0, los demás 0.0

SELECT sala_libre(1, dia(1) + time '09:00', dia(1) + time '11:00')    AS a,   -- f: se cruza con las de Ana y Bruno
       sala_libre(1, dia(1) + time '12:00', dia(1) + time '14:00')    AS b,   -- t: empieza cuando termina la de Bruno
       sala_libre(2, dia(3) + time '08:00', dia(3) + time '10:00')    AS c,   -- t: la que había está cancelada
       sala_libre(1, dia(1) + time '08:00', dia(1) + time '10:00', 1) AS d;   -- t: la única que choca es la 1, excluida
```

**A3. Procedimientos (15 min).** (a) Escribir `reservar(p_codigo, p_sala, p_inicio, p_fin, p_asistentes)` en PL/pgSQL, que verifique en este orden las reglas 5, 2, 3 y 4 (con un `RAISE EXCEPTION` claro para cada una, incluyendo estudiante o sala inexistente) e inserte la reserva, con un `RAISE NOTICE` que diga su número. Usar las funciones de A2. (b) Escribir `cancelar(p_id integer)` para la regla 6. (c) Correr la batería:

| # | Llamada | Resultado esperado |
|---|---|---|
| 1 | `CALL reservar('2610005', 1, dia(4) + time '08:00', dia(4) + time '10:00', 2);` | Error: Elena está sancionada |
| 2 | `CALL reservar('2610006', 4, dia(4) + time '08:00', dia(4) + time '10:00', 2);` | Error: sala en mantenimiento |
| 3 | `CALL reservar('2610006', 1, dia(4) + time '08:00', dia(4) + time '10:00', 5);` | Error: capacidad 4, no 5 |
| 4 | `CALL reservar('2610006', 1, dia(1) + time '09:00', dia(1) + time '11:00', 2);` | Error: sala ocupada |
| 5 | `CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '10:00', 3);` | Error: Ana superaría las 6 horas (lleva 5.0) |
| 6 | `CALL reservar('2610006', 1, dia(1) + time '12:00', dia(1) + time '14:00', 3);` | Reserva creada |
| 7 | `CALL reservar('2610004', 2, dia(3) + time '08:00', dia(3) + time '10:00', 4);` | Reserva creada (la anterior estaba cancelada) |
| 8 | `CALL reservar('2610001', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);` | Reserva creada (Ana llega justo a 6) |
| 9 | `CALL reservar('2610099', 2, dia(4) + time '08:00', dia(4) + time '09:00', 3);` | Error: el estudiante no existe |
| 10 | `CALL cancelar(7);` | Error: la reserva 7 no está activa |
| 11 | `CALL cancelar(2);` | Cancela la reserva de Bruno |

**A4. Trigger de validación (15 min).** (a) Antes de crear el trigger, comprobar que las reglas 2 y 3 se pueden saltar:

```sql
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);   -- pasa: 12 personas en una sala de 10, cruzada con la de Ana
ROLLBACK;
```

(b) Escribir la función `validar_reserva()` y el trigger `reserva_validar`, `BEFORE INSERT OR UPDATE` por fila, que impongan las reglas 2 y 3 a toda reserva **activa** (si `NEW.estado` no es `'activa'`, se deja pasar sin validar). Usar `sala_libre` con `p_excluir`: ¿qué pasaría al modificar una reserva si no se excluyera a sí misma? (c) Correr la batería:

```sql
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 12);   -- debe fallar: capacidad
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + time '10:00', dia(2) + time '11:00', 6);    -- debe fallar: sala ocupada
UPDATE reserva SET inicio = dia(3) + time '09:00' WHERE id = 6;            -- debe fallar: se cruza con la de Diego de las 8:00
UPDATE reserva SET asistentes = 5 WHERE id = 6;                            -- debe pasar
UPDATE reserva SET estado = 'activa' WHERE id = 5;                         -- debe fallar: reactivarla la cruza
```

(d) Elena está sancionada y el primer `INSERT` de (a) igual pasaba. ¿Las reglas 4 y 5 deberían estar también en el trigger, o solo en el procedimiento? Argumentar pensando en quién más escribe en `reserva` (por ejemplo, la coordinación, que reserva la sala C para un evento de 4 horas a nombre de un monitor).

**A5. Trigger que reacciona a un cambio de estado (5 min).** Escribir `sancionar_inasistencia()` y el trigger `reserva_sancionar`, `AFTER UPDATE OF estado` por fila, con una cláusula **`WHEN`** que lo limite al paso a `'no_asistio'` desde otro estado, y que ponga `sancionado_hasta` en hoy más 7 días. La sintaxis de `WHEN` va entre `FOR EACH ROW` y `EXECUTE FUNCTION`: `WHEN (NEW.estado = … AND OLD.estado <> …)`.

```sql
UPDATE reserva SET estado = 'no_asistio' WHERE id = 7;    -- Felipe no se presentó (se corrige el estado)
SELECT codigo, nombre, sancionado_hasta - CURRENT_DATE AS dias
FROM   estudiante WHERE sancionado_hasta IS NOT NULL;     -- Elena 30, Felipe 7
CALL reservar('2610006', 3, dia(5) + time '08:00', dia(5) + time '10:00', 2);   -- debe fallar: Felipe sancionado
UPDATE reserva SET asistentes = 2 WHERE id = 8;           -- Bruno: ya era no_asistio; ¿queda sancionado?
```

¿Por qué el último `UPDATE` no sanciona a Bruno? ¿Qué pasaría sin el `WHEN`?

**A6. Ciclo o conjunto (5 min).** La reserva 9 ya pasó y sigue `activa`. Un compañero escribió este procedimiento para cerrar las reservas vencidas:

```sql
CREATE PROCEDURE cerrar_vencidas_ciclo()
LANGUAGE plpgsql
AS $$
DECLARE
    r  record;
BEGIN
    FOR r IN SELECT id FROM reserva WHERE estado = 'activa' AND fin < now() LOOP
        UPDATE reserva SET estado = 'cumplida' WHERE id = r.id;
        RAISE NOTICE 'Reserva % cerrada', r.id;
    END LOOP;
END;
$$;
```

(a) Reescribirlo como `cerrar_vencidas()`, con `LANGUAGE sql` y **una sola sentencia**, y correrlo. (b) Con 2 000 reservas vencidas, ¿cuántas sentencias `UPDATE` ejecuta cada versión? ¿Y cuántas veces se dispara el trigger `reserva_validar` en cada una?

**Reto (opcional): la regla 3 como restricción.** PostgreSQL tiene una restricción que S21 no presentó: `EXCLUDE`, que generaliza `UNIQUE` a cualquier operador. Con la extensión `btree_gist`, "dos reservas activas de la misma sala no se cruzan" se puede declarar:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE reserva ADD CONSTRAINT reserva_sin_cruce
    EXCLUDE USING gist (id_sala WITH =, tsrange(inicio, fin) WITH &&)
    WHERE (estado = 'activa');
```

(`tsrange(inicio, fin)` es el intervalo como un valor, y `&&` significa "se cruzan".) Desactivar el trigger (`ALTER TABLE reserva DISABLE TRIGGER reserva_validar;`), probar un `INSERT` que se cruce y otro que no, y volver a activarlo. Según la tabla de S21 (sección 8), ¿qué debería quedar en el trigger si se usa esta restricción?

### Parte B: Hito 4 sobre el esquema propio

1. **Escoger qué programar.** Como mínimo, **un procedimiento** y **un trigger** con propósito real (S21, sección 9). Antes de escribir, anotar para cada uno: qué regla o caso de uso del documento del proyecto resuelve (sección 3.1 o 3.2) y por qué ese mecanismo y no otro (S21, sección 8). Opciones típicas:

   | Tipo | Opción |
   |---|---|
   | Procedimiento | Registrar un préstamo con todas sus validaciones; registrar una devolución con sus efectos |
   | Trigger `BEFORE` | Impedir el préstamo a un lector en mora o con el máximo de préstamos abiertos; impedir dos préstamos abiertos del mismo ejemplar (o mejor, el índice único parcial de S21) |
   | Trigger `AFTER` | Mantener el dato desnormalizado que el grupo decidió guardar en el Hito 3 (`ejemplares_disponibles`, por ejemplo); auditar préstamos o cambios de cuentas |
   | Función de apoyo | La definición de mora; la disponibilidad de un libro |

   Si en el Hito 3 el grupo dejó un dato desnormalizado "pendiente de un trigger", ese trigger **no es opcional**: es parte de lo que se dijo en el documento de normalización.

2. **Escribirlos** en `postgres/scripts/programacion.sql`, con un comentario arriba de cada objeto que diga qué regla implementa. Usar `CREATE OR REPLACE FUNCTION` / `CREATE OR REPLACE PROCEDURE` y `DROP TRIGGER IF EXISTS … ;` antes de cada `CREATE TRIGGER`, para que el archivo se pueda correr varias veces mientras se prueba.

3. **Probarlos** con un archivo `postgres/scripts/pruebas-programacion.sql`, al estilo de las baterías de la parte A: para cada regla, al menos un caso que debe pasar y uno que debe fallar, con el resultado esperado en un comentario. Los casos se construyen sobre `datos-prueba.sql` de S16 (lectores en mora, lectores con el máximo de préstamos, libros sin ejemplares libres). Si el trigger mantiene un dato desnormalizado, la prueba incluye la consulta de verificación de S20 antes y después.

4. **Llevarlos a `postgres/init/`** cuando funcionen, para que una base vacía quede creada con ellos (por ejemplo, como `03_programacion.sql`, después del esquema y antes de los datos si los triggers deben validar la carga, o después de los datos si no). Probarlo en una base aparte, como en S20:

   ```bash
   docker compose exec postgres psql -U curso -d curso -c "CREATE DATABASE prueba_init;"
   docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
   # ... los demás archivos de init/ en orden ...
   docker compose exec postgres psql -U curso -d curso -c "DROP DATABASE prueba_init;"
   ```

5. **Preparar la evidencia**: un video de 2 a 3 minutos (o una secuencia de pantallazos) donde se vea, con datos del proyecto, el procedimiento ejecutándose, el trigger **rechazando** una operación que viola la regla y, si aplica, el trigger **actualizando** otra tabla (consulta antes, operación, consulta después).

6. **Documentar en el README del proyecto** una sección "Lógica en la base de datos" con una tabla: objeto, tipo (función, procedimiento, trigger), tabla y evento (para los triggers), y regla que implementa. Es lo que evita el problema de "lógica invisible" (S21, sección 6.6), y en M7 la API va a llamar estos procedimientos.

## Entregable

**Por grupo:**

1. Al terminar la sesión: `S22-grupo.sql` con todo el SQL de la parte A (A1 a A6, y el reto si se hizo), y un documento corto con las respuestas de A1 (b) y (d), A4 (b) y (d), A5 y A6 (b).
2. En la fecha del Hito 4, en el repositorio del grupo: `postgres/scripts/programacion.sql`, `postgres/scripts/pruebas-programacion.sql`, `postgres/init/` actualizado, la sección del README y la evidencia (video o pantallazos).

## Checkpoint del Hito 4

| Pieza (rúbrica del Hito 4) | Dónde queda | Qué revisar |
|---|---|---|
| Procedimiento almacenado funcional | `programacion.sql`; casos en `pruebas-programacion.sql` | Cubre el caso de uso completo y falla con mensajes claros en los casos inválidos |
| Trigger con propósito real de negocio | `programacion.sql`; sección del README | Responde a una regla del documento del proyecto; no es un ejemplo de relleno; no intenta reaccionar al paso del tiempo (S21, sección 6.5) |
| Evidencia de funcionamiento | Video o pantallazos | Se ve el trigger rechazando o actualizando, con datos del proyecto y consulta antes y después |

## Rúbrica de la parte A (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Restricciones y funciones (A1, A2)** | Faltan restricciones o funciones, o no corren | Corren, pero alguna prueba no da el resultado esperado o falta justificar las acciones de las FK | Las cuatro restricciones y las dos funciones dan los resultados esperados; acciones de las FK justificadas; A1 (d) identifica que las reglas entre filas no caben en un `CHECK` |
| **Procedimientos (A3)** | No corren | La batería da algún resultado distinto al esperado, o los mensajes de error no permiten saber qué regla falló | Las 11 pruebas dan el resultado esperado, con mensajes claros, reutilizando las funciones de A2 |
| **Triggers y conjunto (A4, A5, A6)** | Sin triggers, o no se disparan | Los triggers se disparan pero alguna prueba falla (típicamente, el `UPDATE` de asistentes por no excluir la propia reserva) o faltan las respuestas | Las baterías de A4 y A5 dan lo esperado; A4 (d) argumenta dónde van las reglas 4 y 5; A6 en una sentencia y con el conteo correcto |

Máximo 6 puntos por grupo. El Hito 4 se califica aparte, con su propia rúbrica (sección 9 del documento del proyecto).
