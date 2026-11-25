# S21. Programación en la base de datos: integridad referencial, funciones, procedimientos y triggers

**Módulo 6, semana 11, sesión 21 · Magistral (consumo asíncrono + espacio breve de preguntas)**

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Elegir la acción de una clave foránea al borrar o actualizar (`NO ACTION`/`RESTRICT`, `CASCADE`, `SET NULL`) según el significado de la relación.
- Escribir restricciones que miran varias columnas de una fila (`CHECK`) o un subconjunto de filas (índice único parcial), y reconocer las reglas que una restricción no puede expresar.
- Escribir funciones en SQL y en PL/pgSQL (variables, `SELECT … INTO`, `IF`, `RAISE EXCEPTION`) y usarlas dentro de consultas.
- Escribir un procedimiento almacenado que ejecuta un caso de uso completo (registrar un préstamo) y explicar en qué se diferencia de una función.
- Escribir triggers `BEFORE` y `AFTER` a nivel de fila para validar una regla de negocio, mantener un dato desnormalizado y auditar cambios, usando `NEW`, `OLD` y `TG_OP`.
- Explicar qué es un cursor y por qué en PL/pgSQL casi siempre basta con un `FOR … IN SELECT` o, mejor, con una sola sentencia sobre el conjunto.
- Decidir dónde va cada regla del proyecto: restricción, trigger, procedimiento o aplicación.

## Guía de lectura

### 1. Por qué programar dentro de la base de datos

En S17 (sección 4.4) se dijo que el diseño relacional busca que **el esquema** haga imposible guardar contradicciones, en vez de confiar en que todos los programas "tengan cuidado". Hasta ahora las herramientas para eso fueron declarativas: `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `NOT NULL`, `CHECK`. Cubren mucho, pero no todo. Las reglas por defecto del proyecto (documento del proyecto, sección 3.2) son un buen ejemplo:

| Regla | ¿La puede expresar una restricción? |
|---|---|
| Un préstamo es de un ejemplar que existe | Sí: FK |
| La fecha esperada de devolución es posterior a la del préstamo | Sí: `CHECK` sobre dos columnas de la misma fila |
| Un ejemplar no puede tener dos préstamos abiertos a la vez | Sí, con un índice único parcial (sección 3.3) |
| Un lector tiene máximo 3 préstamos abiertos | **No**: hay que contar otras filas |
| Un lector en mora no puede pedir prestado | **No**: hay que mirar otras filas y la fecha de hoy |
| `libro.disponibles` debe coincidir con los ejemplares sin préstamo abierto (S20) | **No**: depende de otra tabla |

Para las reglas de la segunda mitad, el DBMS permite escribir **código que corre dentro del servidor**: funciones, procedimientos almacenados y disparadores (*triggers*). En PostgreSQL el lenguaje más usado para eso es **PL/pgSQL**, SQL con variables, condicionales y ciclos. El estándar SQL define un lenguaje equivalente (SQL/PSM); MySQL, SQL Server (T-SQL) y Oracle (PL/SQL) tienen el suyo, con sintaxis distinta pero las mismas ideas.

La ventaja es la misma de las restricciones: una regla escrita en la base se cumple **sin importar quién escriba**, sea la API del proyecto (M7), un script de carga de CSV (S14) o alguien en `psql`. El costo es que es código menos visible que el de la aplicación, y hay que usarlo con criterio (sección 6.6).

### 2. El script de la sesión

El script [`S21-biblioteca-programable.sql`](S21-biblioteca-programable.sql) crea el esquema `programable`: la biblioteca de S15 y S20 en pequeño, ya en 3FN y con la columna desnormalizada `libro.disponibles` que en S20 quedó pendiente de un trigger.

```bash
# desde entorno-docker/, con el archivo copiado en postgres/scripts/
docker compose exec postgres psql -U curso -d curso -f /scripts/S21-biblioteca-programable.sql
docker compose exec postgres psql -U curso -d curso
```

```sql
curso=# SET search_path TO programable;
```

```
libro           (isbn PK, titulo, autor, categoria, disponibles)
ejemplar        (id_ejemplar PK, isbn FK → libro)
lector          (documento PK, nombres, apellidos, correo UNIQUE)
telefono_lector (documento FK → lector, telefono; PK de los dos)
prestamo        (id PK identidad, id_ejemplar FK → ejemplar, documento FK → lector,
                 fecha_prestamo, fecha_esperada, fecha_devolucion)
descuadre       vista: libros cuyo "disponibles" guardado no coincide con el calculado (S20)
```

Las fechas son relativas al día en que se corre el script, así que el estado es siempre el mismo:

| Lector | Situación |
|---|---|
| Mariana, Santiago | Préstamos ya devueltos, ninguno abierto |
| Valentina | 1 préstamo abierto (*Rayuela*), al día |
| Juan David | **3 préstamos abiertos**, al día (el máximo permitido) |
| Camila | 1 préstamo abierto (*El Aleph*) **vencido hace 11 días** |
| Sebastián | Sin préstamos; tiene dos teléfonos registrados |

Las secciones siguientes se hacen en orden, sobre el mismo esquema. Para volver al estado inicial (y borrar todo lo que se haya creado), se corre otra vez el script.

### 3. Integridad referencial y restricciones avanzadas

#### 3.1 Qué pasa al borrar algo referenciado

En S10 se vio que una FK impide insertar un préstamo de un lector que no existe. Falta el otro lado: ¿qué pasa si se borra un lector que **sí** tiene préstamos?

```sql
DELETE FROM lector WHERE documento = '1000000005';   -- Camila
```

```
ERROR:  update or delete on table "lector" violates foreign key constraint "prestamo_documento_fkey" on table "prestamo"
DETAIL:  Key (documento)=(1000000005) is still referenced from table "prestamo".
```

Es el comportamiento por defecto: si al borrar (o al cambiar la PK de) una fila quedarían filas huérfanas en otra tabla, la operación se rechaza. Con Sebastián pasa lo mismo, aunque no tenga préstamos, porque tiene teléfonos:

```sql
DELETE FROM lector WHERE documento = '1000000006';   -- error: telefono_lector_documento_fkey
```

#### 3.2 Las acciones referenciales

Al declarar una FK se puede decir qué hacer cuando se borra (`ON DELETE`) o se actualiza (`ON UPDATE`) la fila referenciada:

| Acción | Qué hace | Cuándo tiene sentido |
|---|---|---|
| `NO ACTION` (por defecto) | Rechaza la operación si deja huérfanos. Se verifica al final de la sentencia | Casi siempre: es la opción segura |
| `RESTRICT` | Igual, pero se verifica de inmediato y no se puede diferir | Cuando se quiere dejar explícito que **nunca** se borra en cascada |
| `CASCADE` | Borra (o actualiza) también las filas que la referencian | La fila hija no tiene sentido sin la padre: teléfonos de un lector, líneas de una factura (la entidad débil de S6) |
| `SET NULL` | Pone la FK de las hijas en `NULL` | La relación es opcional y la hija sigue existiendo: un libro cuya categoría se elimina queda "sin categoría" |
| `SET DEFAULT` | Pone la FK en su valor por defecto | Poco usado |

Los teléfonos de un lector son un atributo multivaluado (S11): no existen sin el lector. Su FK debe ser `CASCADE`:

```sql
ALTER TABLE telefono_lector
  DROP CONSTRAINT telefono_lector_documento_fkey,
  ADD  CONSTRAINT telefono_lector_documento_fkey
       FOREIGN KEY (documento) REFERENCES lector ON DELETE CASCADE;

BEGIN;
DELETE FROM lector WHERE documento = '1000000006';             -- DELETE 1
SELECT count(*) FROM telefono_lector WHERE documento = '1000000006';   -- 0: se fueron con él
ROLLBACK;
```

Los préstamos, en cambio, son **historia**: el reporte de "usuarios que más leen" cuenta préstamos devueltos. Si borrar un lector borrara en cascada sus préstamos, el reporte cambiaría sin que nadie lo notara. Su FK se deja sin cascada, y se hace explícito:

```sql
ALTER TABLE prestamo
  DROP CONSTRAINT prestamo_documento_fkey,
  ADD  CONSTRAINT prestamo_documento_fkey
       FOREIGN KEY (documento) REFERENCES lector ON DELETE RESTRICT;
```

Si un lector se retira de la biblioteca, lo usual no es borrarlo sino **desactivarlo** (una columna `activo boolean`): conserva su historia y deja de poder pedir prestado. Es lo que pide el documento del proyecto ("baja/inactivación").

`ON UPDATE CASCADE` sirve cuando una clave natural puede corregirse (un ISBN mal digitado): el cambio se propaga a las FK que lo referencian. Con claves sustitutas (`id` de identidad) casi nunca hace falta, porque nadie las cambia.

#### 3.3 Restricciones que miran más de una columna o un subconjunto de filas

Un `CHECK` puede comparar varias columnas **de la misma fila**. El script ya trae dos en `prestamo`:

```sql
CHECK (fecha_esperada > fecha_prestamo),
CHECK (fecha_devolucion IS NULL OR fecha_devolucion >= fecha_prestamo)
```

```sql
INSERT INTO prestamo (id_ejemplar, documento, fecha_prestamo, fecha_esperada)
VALUES (10, '1000000002', CURRENT_DATE, CURRENT_DATE - 1);
-- ERROR:  new row for relation "prestamo" violates check constraint "prestamo_check"
```

Otra regla del dominio: un ejemplar físico no puede estar prestado dos veces al mismo tiempo. Hoy nada lo impide:

```sql
BEGIN;
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (2, '1000000002', CURRENT_DATE + 14);       -- el ejemplar 2 ya lo tiene Juan David

SELECT id, id_ejemplar, documento
FROM   prestamo
WHERE  id_ejemplar = 2 AND fecha_devolucion IS NULL;   -- 2 filas: el mismo libro en dos manos
ROLLBACK;
```

Un `UNIQUE (id_ejemplar)` no sirve, porque el ejemplar 2 tiene (y debe poder tener) muchos préstamos **devueltos**. Lo que se quiere es que sea único **entre los préstamos abiertos**. Para eso está el **índice único parcial** (el índice parcial de S20, sección 4, con `UNIQUE`):

```sql
CREATE UNIQUE INDEX prestamo_ejemplar_abierto
    ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;

INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (2, '1000000002', CURRENT_DATE + 14);
-- ERROR:  duplicate key value violates unique constraint "prestamo_ejemplar_abierto"
```

#### 3.4 Lo que una restricción no puede hacer

¿Y la regla de máximo 3 préstamos abiertos? La tentación es un `CHECK` que cuente:

```sql
ALTER TABLE prestamo ADD CHECK (
  (SELECT count(*) FROM prestamo p2
   WHERE p2.documento = documento AND p2.fecha_devolucion IS NULL) <= 3);
-- ERROR:  cannot use subquery in check constraint
```

Un `CHECK` solo ve la fila que se está insertando o modificando. Una regla que necesita **otras filas** (contar, comparar con otra tabla) o **algo que cambia solo** (la fecha de hoy) no se puede declarar: hay que programarla. El estándar SQL define `CREATE ASSERTION` para reglas sobre toda la base, pero prácticamente ningún DBMS lo implementa. Las secciones 5 y 6 resuelven esta regla de dos formas.

### 4. Funciones

#### 4.1 Una función en SQL

Una **función** recibe parámetros, calcula algo y **devuelve un valor**. La más sencilla se escribe en SQL puro: su cuerpo es una consulta, y el resultado es lo que devuelve la consulta.

```sql
CREATE FUNCTION prestamos_abiertos(p_documento varchar) RETURNS bigint
LANGUAGE sql STABLE
AS $$
    SELECT count(*)
    FROM   prestamo
    WHERE  documento = p_documento
      AND  fecha_devolucion IS NULL;
$$;
```

- `$$ … $$` delimita el cuerpo, para no tener que escapar las comillas de adentro.
- El prefijo `p_` en los parámetros es una convención para no confundirlos con las columnas (`p_documento` frente a `documento`).
- `STABLE` le dice al optimizador que la función no modifica la base y que, dentro de una misma consulta, con los mismos argumentos da el mismo resultado. Una función que modifica datos es `VOLATILE` (el valor por defecto); una que solo depende de sus argumentos, como una conversión de unidades, es `IMMUTABLE`.

Una función se usa donde iría una expresión: en el `SELECT`, en el `WHERE`, en otra función.

```sql
SELECT documento, nombres, prestamos_abiertos(documento) AS abiertos
FROM   lector
ORDER BY documento;
```

| documento | nombres | abiertos |
|---|---|---|
| 1000000001 | Mariana | 0 |
| 1000000002 | Santiago | 0 |
| 1000000003 | Valentina | 1 |
| 1000000004 | Juan David | 3 |
| 1000000005 | Camila | 1 |
| 1000000006 | Sebastián | 0 |

La segunda función de la sesión responde si un lector está en mora, con la definición del proyecto (un préstamo abierto cuya fecha esperada ya pasó):

```sql
CREATE FUNCTION en_mora(p_documento varchar) RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT EXISTS (SELECT 1 FROM prestamo
                   WHERE documento = p_documento
                     AND fecha_devolucion IS NULL
                     AND fecha_esperada < CURRENT_DATE);
$$;

SELECT nombres FROM lector WHERE en_mora(documento);   -- Camila
```

Escribir la regla **una vez**, con nombre, tiene una ventaja que va más allá de ahorrar texto: el reporte de morosos de S16, el procedimiento de la sección 5 y el trigger de la sección 6 van a usar exactamente la misma definición de mora. Si la biblioteca decide dar tres días de gracia, se cambia en un solo lugar.

#### 4.2 Una función en PL/pgSQL

Cuando el cálculo necesita pasos, variables o decisiones, se escribe en PL/pgSQL. Un bloque PL/pgSQL tiene esta forma:

```
DECLARE
    -- variables, con su tipo
BEGIN
    -- sentencias: SQL normal, asignaciones (:=), IF, ciclos, RAISE, RETURN
END;
```

La función `estado_prestamo` devuelve un texto que describe un préstamo:

```sql
CREATE FUNCTION estado_prestamo(p_id integer) RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_esperada    date;
    v_devolucion  date;
BEGIN
    SELECT fecha_esperada, fecha_devolucion
    INTO   v_esperada, v_devolucion
    FROM   prestamo
    WHERE  id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el préstamo %', p_id;
    END IF;

    IF v_devolucion IS NOT NULL THEN
        RETURN 'devuelto';
    ELSIF v_esperada < CURRENT_DATE THEN
        RETURN 'en mora (' || (CURRENT_DATE - v_esperada) || ' días)';
    ELSE
        RETURN 'al día';
    END IF;
END;
$$;

SELECT id, documento, estado_prestamo(id) FROM prestamo ORDER BY id;
```

| id | documento | estado_prestamo |
|---|---|---|
| 1 | 1000000001 | devuelto |
| 2 | 1000000001 | devuelto |
| 3 | 1000000004 | al día |
| 4 | 1000000004 | al día |
| 5 | 1000000004 | al día |
| 6 | 1000000005 | en mora (11 días) |
| 7 | 1000000003 | al día |
| 8 | 1000000002 | devuelto |

Lo nuevo frente a SQL:

- **`SELECT … INTO variables`** guarda el resultado de una consulta de una fila en variables. Si la consulta no devuelve filas, las variables quedan en `NULL` y la variable especial **`FOUND`** queda en falso.
- **`IF … ELSIF … ELSE … END IF`**: el condicional.
- **`RAISE EXCEPTION 'mensaje %', valor`** detiene la ejecución con un error; cada `%` se reemplaza por el siguiente argumento. El error se comporta igual que uno del DBMS (sección 5.3). `RAISE NOTICE` muestra un mensaje sin detener nada, útil para depurar.

```sql
SELECT estado_prestamo(99);
-- ERROR:  No existe el préstamo 99
-- CONTEXT:  PL/pgSQL function estado_prestamo(integer) line 12 at RAISE
```

### 5. Procedimientos almacenados

#### 5.1 Un caso de uso completo

Registrar un préstamo, en el mostrador, son varios pasos: verificar que el lector existe, que no está en mora, que no tiene ya 3 préstamos; buscar un ejemplar libre del libro pedido; insertar el préstamo con su fecha esperada. Un **procedimiento almacenado** guarda esa secuencia en la base, con nombre, para que cualquier programa la ejecute con una sola instrucción.

```sql
CREATE PROCEDURE registrar_prestamo(p_documento varchar, p_isbn char(13))
LANGUAGE plpgsql
AS $$
DECLARE
    v_ejemplar  integer;
    v_id        integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM lector WHERE documento = p_documento) THEN
        RAISE EXCEPTION 'El lector % no existe', p_documento;
    END IF;
    IF en_mora(p_documento) THEN
        RAISE EXCEPTION 'El lector % tiene préstamos en mora', p_documento;
    END IF;
    IF prestamos_abiertos(p_documento) >= 3 THEN
        RAISE EXCEPTION 'El lector % ya tiene 3 préstamos abiertos', p_documento;
    END IF;

    -- un ejemplar del libro que no tenga un préstamo abierto
    SELECT e.id_ejemplar INTO v_ejemplar
    FROM   ejemplar e
    WHERE  e.isbn = p_isbn
      AND  NOT EXISTS (SELECT 1 FROM prestamo p
                       WHERE p.id_ejemplar = e.id_ejemplar
                         AND p.fecha_devolucion IS NULL)
    ORDER BY e.id_ejemplar
    LIMIT 1;

    IF v_ejemplar IS NULL THEN
        RAISE EXCEPTION 'No hay ejemplares disponibles del libro %', p_isbn;
    END IF;

    INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
    VALUES (v_ejemplar, p_documento, CURRENT_DATE + 14)
    RETURNING id INTO v_id;

    RAISE NOTICE 'Préstamo % registrado: ejemplar %, devolver el %',
                 v_id, v_ejemplar, CURRENT_DATE + 14;
END;
$$;
```

Un procedimiento se ejecuta con `CALL`. Los cuatro primeros intentos violan una regla cada uno; el quinto pasa:

```sql
CALL registrar_prestamo('1000000005', '9780000000001');  -- ERROR: El lector 1000000005 tiene préstamos en mora
CALL registrar_prestamo('1000000004', '9780000000001');  -- ERROR: El lector 1000000004 ya tiene 3 préstamos abiertos
CALL registrar_prestamo('1000000003', '9780000000005');  -- ERROR: No hay ejemplares disponibles del libro 9780000000005
CALL registrar_prestamo('1000000099', '9780000000005');  -- ERROR: El lector 1000000099 no existe
CALL registrar_prestamo('1000000003', '9780000000001');
-- NOTICE:  Préstamo 12 registrado: ejemplar 1, devolver el …
```

(El número del préstamo puede ser otro: una secuencia de identidad no reutiliza los valores que tomaron los `INSERT` que fallaron en la sección 3.)

La devolución es más corta. Usa `FOUND` después de un `UPDATE`, que queda en verdadero si la sentencia modificó al menos una fila:

```sql
CREATE PROCEDURE registrar_devolucion(p_id integer)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE prestamo
    SET    fecha_devolucion = CURRENT_DATE
    WHERE  id = p_id
      AND  fecha_devolucion IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El préstamo % no existe o ya fue devuelto', p_id;
    END IF;
END;
$$;

CALL registrar_devolucion(7);   -- Valentina devuelve Rayuela
CALL registrar_devolucion(7);   -- ERROR: El préstamo 7 no existe o ya fue devuelto
```

#### 5.2 Función o procedimiento

| | Función | Procedimiento |
|---|---|---|
| Se invoca con | Dentro de una expresión: `SELECT f(x)`, `WHERE f(x)` | `CALL p(x)`, como sentencia sola |
| Devuelve | Un valor (o una tabla) | Nada (puede tener parámetros `OUT`) |
| Para qué se usa | Calcular algo: una regla, un estado, un dato derivado | Ejecutar una acción completa: un caso de uso que modifica datos |
| Control de transacciones | No puede hacer `COMMIT` | Puede hacer `COMMIT` dentro (útil en procesos largos por lotes) |

`CREATE PROCEDURE` existe en PostgreSQL desde la versión 11; antes, todo se hacía con funciones que devolvían `void`, y todavía se ve mucho código así. Una buena regla: si se usaría en un `SELECT`, es función; si es "lo que pasa cuando el bibliotecario oprime *Registrar préstamo*", es procedimiento. En M7 la API va a llamar estos procedimientos en vez de repetir sus pasos en JavaScript.

#### 5.3 Un error deshace todo el procedimiento

Un `CALL` es una sentencia, y como toda sentencia es atómica: si algo falla en la mitad (un `RAISE EXCEPTION`, una FK violada, el índice único de la sección 3.3), **se deshace todo lo que el procedimiento alcanzó a hacer**. No queda un préstamo a medio registrar. Si el `CALL` está dentro de un `BEGIN … COMMIT` más grande, el error aborta esa transacción completa (S13). Esa es otra razón para poner los casos de uso en la base: la atomicidad viene incluida.

#### 5.4 Lo que el procedimiento no cubre

Los procedimientos ya funcionan, pero quedan dos problemas.

El primero: la regla de los 3 préstamos solo se cumple si **todos** registran préstamos con `registrar_prestamo`. Nada impide un `INSERT` directo:

```sql
BEGIN;
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (10, '1000000004', CURRENT_DATE + 14);      -- pasa
SELECT prestamos_abiertos('1000000004');           -- 4
ROLLBACK;
```

El segundo: ninguno de los dos procedimientos actualiza `libro.disponibles`. La vista de verificación de S20 lo muestra:

```sql
SELECT * FROM descuadre;
```

| isbn | titulo | guardado | calculado |
|---|---|---|---|
| 9780000000004 | Rayuela | 1 | 2 |
| 9780000000001 | Cien años de soledad | 2 | 1 |

Rayuela tiene un ejemplar más de los que dice (Valentina lo devolvió) y Cien años de soledad uno menos (se le prestó a Valentina). Se podría agregar un `UPDATE libro …` a cada procedimiento, pero el `INSERT` directo de arriba seguiría saltándoselo. Los dos problemas tienen la misma solución: que sea el DBMS el que reaccione a cada cambio en `prestamo`, venga de donde venga.

### 6. Disparadores (triggers)

#### 6.1 Anatomía de un trigger

Un **trigger** es código que el DBMS ejecuta **automáticamente** cuando ocurre un evento sobre una tabla. Nadie lo llama: se dispara. En PostgreSQL tiene dos partes:

1. Una **función de trigger**: una función PL/pgSQL sin parámetros que `RETURNS trigger`. Adentro tiene variables especiales:

   | Variable | Contiene |
   |---|---|
   | `NEW` | La fila nueva (en `INSERT` y `UPDATE`). En un trigger `BEFORE` se puede modificar |
   | `OLD` | La fila anterior (en `UPDATE` y `DELETE`) |
   | `TG_OP` | La operación que lo disparó: `'INSERT'`, `'UPDATE'` o `'DELETE'` |

2. La declaración **`CREATE TRIGGER`**, que dice cuándo se ejecuta esa función:

   ```
   CREATE TRIGGER nombre
   {BEFORE | AFTER} {INSERT | UPDATE [OF columnas] | DELETE} [OR …] ON tabla
   FOR EACH {ROW | STATEMENT}
   EXECUTE FUNCTION funcion();
   ```

   - **`BEFORE`** corre antes de escribir la fila: sirve para **validar** (rechazar con `RAISE EXCEPTION`) o **completar** la fila (modificar `NEW`). Debe devolver `NEW` para que la operación siga; si devuelve `NULL`, la fila se descarta en silencio.
   - **`AFTER`** corre después de escribir la fila: sirve para **reaccionar** (actualizar otra tabla, auditar). Su valor de retorno se ignora; por convención, `RETURN NULL`.
   - **`FOR EACH ROW`** ejecuta la función una vez por fila afectada; **`FOR EACH STATEMENT`**, una vez por sentencia, aunque afecte mil filas o ninguna. En esta sesión todos son por fila.

Se usan los tres patrones más comunes.

#### 6.2 Trigger de validación: la regla vale para todos

```sql
CREATE FUNCTION validar_prestamo() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF en_mora(NEW.documento) THEN
        RAISE EXCEPTION 'El lector % tiene préstamos en mora', NEW.documento;
    END IF;
    IF prestamos_abiertos(NEW.documento) >= 3 THEN
        RAISE EXCEPTION 'El lector % ya tiene 3 préstamos abiertos', NEW.documento;
    END IF;
    -- si no se dio la fecha esperada, se pone la del plazo estándar
    IF NEW.fecha_esperada IS NULL THEN
        NEW.fecha_esperada := NEW.fecha_prestamo + 14;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER prestamo_validar
BEFORE INSERT ON prestamo
FOR EACH ROW
EXECUTE FUNCTION validar_prestamo();
```

El mismo `INSERT` directo de la sección 5.4 ya no pasa, y un préstamo sin fecha esperada la recibe del trigger:

```sql
INSERT INTO prestamo (id_ejemplar, documento, fecha_esperada)
VALUES (10, '1000000004', CURRENT_DATE + 14);
-- ERROR:  El lector 1000000004 ya tiene 3 préstamos abiertos

BEGIN;
INSERT INTO prestamo (id_ejemplar, documento) VALUES (10, '1000000002')
RETURNING id, fecha_prestamo, fecha_esperada;      -- fecha_esperada = hoy + 14
ROLLBACK;
```

`fecha_esperada` es `NOT NULL` y aun así el segundo `INSERT` funciona: el `NOT NULL` se verifica **después** de los triggers `BEFORE`, sobre la fila ya completada.

Ahora las validaciones de mora y de máximo están en dos lugares: en `registrar_prestamo` y en el trigger. El trigger es la red de seguridad que no se puede saltar; las del procedimiento se pueden dejar (dan el error antes de buscar ejemplar) o quitar, pero si se dejan, deben usar las mismas funciones `en_mora` y `prestamos_abiertos`, para que la regla siga escrita una sola vez.

#### 6.3 Trigger de mantenimiento: el dato desnormalizado no miente

En S20 se dejó `libro.disponibles` con una consulta de verificación (`descuadre`) y la promesa de un trigger. La primera idea es sumar o restar 1 en cada evento: préstamo nuevo, resta; devolución, suma; borrado de un préstamo abierto, suma. Funciona en esos tres casos, pero hay más: una devolución que se "deshace" porque se registró por error (`fecha_devolucion` vuelve a `NULL`), un préstamo al que se le corrige el ejemplar. Cada caso olvidado es un descuadre. Es más seguro **recalcular** los libros afectados, con el mismo cálculo de S20:

```sql
CREATE FUNCTION actualizar_disponibles() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE libro l
    SET    disponibles = (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
                       - (SELECT count(*)
                          FROM   prestamo p JOIN ejemplar e USING (id_ejemplar)
                          WHERE  e.isbn = l.isbn AND p.fecha_devolucion IS NULL)
    WHERE  l.isbn IN (SELECT isbn FROM ejemplar
                      WHERE  id_ejemplar IN (NEW.id_ejemplar, OLD.id_ejemplar));
    RETURN NULL;
END;
$$;

CREATE TRIGGER prestamo_disponibles
AFTER INSERT OR DELETE OR UPDATE OF id_ejemplar, fecha_devolucion ON prestamo
FOR EACH ROW
EXECUTE FUNCTION actualizar_disponibles();
```

- Se usan `NEW` **y** `OLD` porque, si se cambia el ejemplar de un préstamo, cambian dos libros: el de antes y el de ahora. En un `INSERT`, `OLD` es `NULL`; en un `DELETE`, `NEW` es `NULL`; el `IN` ignora el que falte.
- `UPDATE OF id_ejemplar, fecha_devolucion` evita que el trigger corra cuando se cambia otra columna (por ejemplo, la fecha esperada), que no afecta la disponibilidad.
- Es `AFTER`: cuando corre, la fila de `prestamo` ya está escrita y el recálculo la incluye.

El trigger mantiene la copia desde ahora, pero no corrige el descuadre que dejaron los procedimientos de la sección 5. Se arregla una vez, y se comprueba que el trigger lo sostiene:

```sql
UPDATE libro l SET disponibles = d.calculado
FROM   descuadre d WHERE d.isbn = l.isbn;               -- UPDATE 2

SELECT * FROM descuadre;                                 -- 0 filas
CALL registrar_prestamo('1000000002', '9780000000009');  -- Quijote: disponibles pasa de 2 a 1
SELECT titulo, disponibles FROM libro WHERE isbn = '9780000000009';
SELECT * FROM descuadre;                                 -- sigue en 0 filas
```

`registrar_prestamo` no cambió: el trigger se dispara por el `INSERT` que el procedimiento hace adentro. Igual pasaría con un `INSERT` desde la API, desde `psql` o desde un `COPY` de carga masiva (S14), que también dispara los triggers de fila.

#### 6.4 Trigger de auditoría: quién cambió qué

La tercera aplicación típica es guardar un registro de los cambios. La tabla de auditoría guarda la fila antes y después del cambio como `jsonb` (un tipo de PostgreSQL para documentos JSON, como los de MongoDB en S4), para no tener que repetir todas las columnas de `prestamo`:

```sql
CREATE TABLE auditoria_prestamo (
    id           bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operacion    text         NOT NULL,
    id_prestamo  integer      NOT NULL,
    usuario      text         NOT NULL DEFAULT current_user,
    momento      timestamptz  NOT NULL DEFAULT now(),
    antes        jsonb,
    despues      jsonb
);

CREATE FUNCTION auditar_prestamo() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria_prestamo (operacion, id_prestamo, antes, despues)
        VALUES (TG_OP, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
    ELSE  -- DELETE
        INSERT INTO auditoria_prestamo (operacion, id_prestamo, antes)
        VALUES (TG_OP, OLD.id, to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER prestamo_auditar
AFTER UPDATE OR DELETE ON prestamo
FOR EACH ROW
EXECUTE FUNCTION auditar_prestamo();
```

```sql
UPDATE prestamo SET fecha_esperada = fecha_esperada + 7 WHERE id = 3;   -- se amplía el plazo

BEGIN;
DELETE FROM prestamo WHERE id = 4;
SELECT operacion, id_prestamo, usuario,
       antes ->> 'fecha_esperada'   AS esperada_antes,
       despues ->> 'fecha_esperada' AS esperada_despues
FROM   auditoria_prestamo ORDER BY id;
ROLLBACK;
```

| operacion | id_prestamo | usuario | esperada_antes | esperada_despues |
|---|---|---|---|---|
| UPDATE | 3 | curso | (hoy + 4) | (hoy + 11) |
| DELETE | 4 | curso | (hoy + 6) | |

Después del `ROLLBACK`, la fila del `DELETE` ya no está en la auditoría: el trigger corre **dentro de la misma transacción** que el cambio que audita, y se deshace con él. Es lo correcto (no se audita algo que no pasó), y es la misma atomicidad de la sección 5.3.

`usuario` guarda el **rol de PostgreSQL** que hizo el cambio. Hoy siempre es `curso`; en M7, cuando cada perfil del proyecto tenga su propio rol, esta columna va a decir si fue el bibliotecario o el administrador.

#### 6.5 Lo que un trigger no puede hacer: el paso del tiempo

Es tentador pensar en "un trigger que marque el préstamo como en mora cuando se vence el plazo". No existe: un trigger responde a un `INSERT`, `UPDATE` o `DELETE`, y cuando un préstamo se vence **no pasa nada en la base**; solo cambia la fecha de hoy. Para la mora hay dos caminos correctos:

- **Calcularla al consultar**, como hacen `en_mora` y `estado_prestamo`: nunca está desactualizada. Es lo que se recomienda para el proyecto.
- Si de verdad hace falta guardarla (por rendimiento, S20), un **proceso programado** que corra cada noche un procedimiento que la actualice. PostgreSQL no trae un programador de tareas; se usa la extensión `pg_cron` o el `cron` del sistema operativo. Está fuera del alcance del curso.

Un trigger sí puede **usar** la mora en el momento de un evento: es lo que hace `validar_prestamo` al impedir un préstamo nuevo a quien está en mora.

#### 6.6 Cuidados con los triggers

- **Son invisibles.** Quien lee `INSERT INTO prestamo …` en la API no ve que eso actualiza `libro` y escribe en `auditoria_prestamo`. Hay que documentarlos (en el README del proyecto) y nombrarlos con claridad. `\dS prestamo` en `psql` lista los triggers de una tabla.
- **Se encadenan.** El `UPDATE libro` de un trigger podría disparar triggers de `libro`, y así. Un trigger que modifica la misma tabla que lo disparó puede llamarse a sí mismo sin fin. Conviene que cada trigger haga una sola cosa, sobre otra tabla.
- **Corren por cada fila.** Una carga de 10 000 préstamos ejecuta `actualizar_disponibles` 10 000 veces. Para cargas masivas a veces se desactivan (`ALTER TABLE … DISABLE TRIGGER …`), se carga y se recalcula una sola vez al final.
- **El orden.** Si una tabla tiene varios triggers para el mismo evento y momento, PostgreSQL los ejecuta en orden alfabético por nombre.

### 7. Nota breve: cursores y ciclos

Un **cursor** es un apuntador a las filas del resultado de una consulta, que permite procesarlas **una a la vez**. Es un concepto anterior a los lenguajes como PL/pgSQL: en SQL embebido en C o COBOL, y en los drivers de Java o Node.js, es la forma de leer un resultado grande sin traerlo todo a memoria. PL/pgSQL tiene cursores explícitos (`DECLARE c CURSOR FOR …`, `OPEN`, `FETCH`, `CLOSE`), pero casi siempre basta con el ciclo **`FOR registro IN consulta LOOP`**, que abre, recorre y cierra el cursor por debajo.

Ejemplo: generar un aviso por cada préstamo en mora (la "notificación de mora" del proyecto es una lista de avisos, sin envío real).

```sql
CREATE TABLE aviso_mora (
    id           integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_prestamo  integer  NOT NULL REFERENCES prestamo,
    fecha        date     NOT NULL DEFAULT CURRENT_DATE,
    mensaje      text     NOT NULL
);

CREATE PROCEDURE generar_avisos_mora()
LANGUAGE plpgsql
AS $$
DECLARE
    r  record;
BEGIN
    FOR r IN
        SELECT p.id, l.nombres, l.correo, b.titulo, CURRENT_DATE - p.fecha_esperada AS dias
        FROM   prestamo p
        JOIN   lector   l USING (documento)
        JOIN   ejemplar e USING (id_ejemplar)
        JOIN   libro    b USING (isbn)
        WHERE  p.fecha_devolucion IS NULL
          AND  p.fecha_esperada < CURRENT_DATE
    LOOP
        INSERT INTO aviso_mora (id_prestamo, mensaje)
        VALUES (r.id, format('%s: "%s" lleva %s días de mora. Escribir a %s',
                             r.nombres, r.titulo, r.dias, r.correo));
        RAISE NOTICE 'Aviso para %', r.correo;
    END LOOP;
END;
$$;

CALL generar_avisos_mora();
-- NOTICE:  Aviso para camila.hernandez@correo-ejemplo.edu.co
SELECT id_prestamo, mensaje FROM aviso_mora;
-- 6 | Camila: "El Aleph" lleva 11 días de mora. Escribir a camila.hernandez@…
```

Funciona, pero el ciclo hace lo mismo que **una sola sentencia** sobre el conjunto:

```sql
INSERT INTO aviso_mora (id_prestamo, mensaje)
SELECT p.id, format('%s: "%s" lleva %s días de mora. Escribir a %s',
                    l.nombres, b.titulo, CURRENT_DATE - p.fecha_esperada, l.correo)
FROM   prestamo p
JOIN   lector   l USING (documento)
JOIN   ejemplar e USING (id_ejemplar)
JOIN   libro    b USING (isbn)
WHERE  p.fecha_devolucion IS NULL
  AND  p.fecha_esperada < CURRENT_DATE;
```

La versión de conjunto es más corta y, con muchas filas, mucho más rápida: el optimizador procesa todo de una vez en vez de ejecutar un `INSERT` por fila. Es la misma idea del álgebra relacional (S9): SQL opera sobre relaciones completas. La regla práctica: **primero se intenta con una sentencia**; el ciclo se reserva para cuando cada fila necesita algo que SQL no hace, como llamar a otro procedimiento que puede fallar, o decidir con lógica complicada qué hacer con ella.

### 8. Dónde va cada regla

| Mecanismo | Úsese para | Ejemplo del proyecto |
|---|---|---|
| `NOT NULL`, `CHECK`, `UNIQUE`, FK | Todo lo que se pueda declarar sobre una fila o una relación | Fechas coherentes, correo único, préstamo de un ejemplar que existe |
| Índice único parcial | Unicidad sobre un subconjunto de filas | Un ejemplar, un solo préstamo abierto |
| Acción referencial (`CASCADE`, …) | Qué pasa con las filas hijas al borrar la padre | Teléfonos de un lector |
| Función | Una regla o un cálculo que se usa en varios lugares | `en_mora`, `prestamos_abiertos` |
| Procedimiento | Un caso de uso completo, atómico | `registrar_prestamo`, `registrar_devolucion` |
| Trigger `BEFORE` | Validar una regla entre filas que nadie debe poder saltarse; completar valores | Máximo 3 préstamos, sin préstamos en mora |
| Trigger `AFTER` | Mantener datos derivados, auditar | `libro.disponibles`, `auditoria_prestamo` |
| Consulta o vista | Lo que depende del paso del tiempo | Préstamos en mora, morosos |
| La aplicación (M7) | Lo que es presentación o flujo de pantallas, no regla de los datos | Qué botones ve cada perfil, mensajes amigables a partir de los errores de la base |

El orden importa: se empieza por arriba. Un trigger que hace lo que podía hacer un `CHECK` es más lento, más difícil de leer y más fácil de romper.

### 9. Mirando el proyecto: el Hito 4

El Hito 4 pide **al menos un procedimiento almacenado y un trigger con propósito real**, con una demo que muestre el trigger disparándose (documento del proyecto, secciones 8 y 9; rúbrica de 6 puntos). Los candidatos naturales en la biblioteca:

- **Procedimientos:** registrar un préstamo, registrar una devolución "completa con sus efectos", la carga masiva de S14 envuelta en un procedimiento.
- **Triggers:** validar máximo de préstamos y mora al prestar; mantener la desnormalización que el grupo decidió en el Hito 3 (S20, parte B, punto 4), si la hay; auditar préstamos o cambios en las cuentas de bibliotecario.
- **Funciones** de apoyo: la definición de mora, la disponibilidad de un libro.

Lo que la rúbrica llama "ejemplo de relleno" es un trigger que no responde a ninguna regla del documento del proyecto (por ejemplo, uno que convierte nombres a mayúsculas). Y ojo con la sección 6.5: un trigger "que marque en mora al vencer el plazo" no se dispara solo; si el grupo quiere un trigger relacionado con la mora, el correcto es el que **impide** prestar a quien está en mora. En S22 (laboratorio) se practica primero sobre otro dominio y después cada grupo construye el suyo.

### 10. Resumen

| Concepto | Qué es | En la sesión |
|---|---|---|
| Acción referencial | Qué hace una FK cuando se borra o actualiza la fila referenciada | `CASCADE` en teléfonos, `RESTRICT` en préstamos |
| `CHECK` de varias columnas | Regla sobre una fila completa | `fecha_esperada > fecha_prestamo` |
| Índice único parcial | `UNIQUE` solo entre las filas que cumplen una condición | Un préstamo abierto por ejemplar |
| Límite de las restricciones | No ven otras filas ni el paso del tiempo | `CHECK` con subconsulta: error |
| Función | Recibe parámetros y devuelve un valor; se usa en expresiones | `en_mora(documento)` |
| PL/pgSQL | SQL con variables, `IF`, ciclos y `RAISE` | `estado_prestamo(id)` |
| Procedimiento | Un caso de uso con nombre; se ejecuta con `CALL`; atómico | `registrar_prestamo` |
| Trigger `BEFORE` fila | Corre antes de escribir; valida o completa `NEW` | `validar_prestamo` |
| Trigger `AFTER` fila | Corre después; actualiza otras tablas o audita | `actualizar_disponibles`, `auditar_prestamo` |
| `NEW`, `OLD`, `TG_OP` | Fila nueva, fila anterior, operación | Recalcular los libros de `NEW` y `OLD` |
| Cursor / `FOR … IN SELECT` | Recorrer un resultado fila por fila | Avisos de mora, mejor como `INSERT … SELECT` |

En **S22** (laboratorio) se escriben funciones, procedimientos y triggers para un sistema de reservas de salas y luego para el proyecto (Hito 4). En **S23** es el Parcial 2 (M4 a M6).

## Lectura del libro

**Silberschatz, Korth, Sudarshan, *Fundamentos de Bases de Datos*, 6ª ed.**

- Capítulo 4, "SQL intermedio": sección 4.4 (restricciones de integridad), en especial la integridad referencial y las acciones en cascada.
- Capítulo 5, "SQL avanzado": secciones 5.2 (funciones y procedimientos) y 5.3 (disparadores). La sección 5.1 (SQL incorporado y cursores) en lectura rápida.

El libro usa la sintaxis del estándar SQL (SQL/PSM); la de PostgreSQL cambia en detalles (`LANGUAGE plpgsql`, `$$`, `EXECUTE FUNCTION`). Para la sintaxis exacta, la documentación de PostgreSQL: capítulo "PL/pgSQL - SQL Procedural Language" y la página de `CREATE TRIGGER`.


## Videos de YouTube alternativos

- [PL/pgSQL funciones y procedimientos PostgreSQL](https://www.youtube.com/watch?v=tB2tjhWQZlM)
- [triggers PostgreSQL tutorial español](https://www.youtube.com/watch?v=KT6TJ7NChcg)

