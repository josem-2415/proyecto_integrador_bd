# S15. Consultas avanzadas: joins externos, agregación, subconsultas y división

**Módulo 4, semana 8, sesión 15 · Magistral (consumo asíncrono + espacio breve de preguntas)**

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Elegir entre `JOIN`, `LEFT JOIN`, `RIGHT JOIN` y `FULL JOIN` según qué filas sin pareja deban conservarse, y usar `LEFT JOIN … WHERE … IS NULL` para encontrar "los que no tienen".
- Resumir filas con `COUNT`, `SUM`, `AVG`, `MIN` y `MAX`, agrupar con `GROUP BY` y filtrar grupos con `HAVING`, explicando en qué se diferencia de `WHERE`.
- Contar bien los ceros: distinguir `COUNT(*)` de `COUNT(columna)` cuando hay un join externo.
- Escribir subconsultas escalares, con `IN` y con `EXISTS` / `NOT EXISTS` (incluidas las correlacionadas), y reconocer la trampa de `NOT IN` con `NULL`.
- Resolver una consulta de "los que … **todos** …" (la división de S9) con `NOT EXISTS` doble, y explicar de dónde sale esa forma usando el cálculo relacional de tuplas.
- Escribir los cuatro reportes del proyecto de biblioteca sobre un esquema mínimo y reconocer qué decisiones dependen del esquema de cada grupo.

## Guía de lectura

### 1. Lo que le falta a S13 para escribir un reporte

Con lo de S13 ya se puede filtrar, proyectar y combinar tablas. Pero los reportes del proyecto piden tres cosas más:

| El reporte pide… | Ejemplo del proyecto | Se resuelve con |
|---|---|---|
| Conservar filas que no tienen pareja | Un libro que nunca se ha prestado debe aparecer con 0 | Joins externos (sección 3) |
| Resumir muchas filas en un número por grupo | Cuántas veces se prestó **cada** libro | Agregación (sección 4) |
| Preguntar por la existencia de otras filas | Lectores que **tienen** al menos un préstamo vencido | Subconsultas (sección 5) |

Y una cuarta que aparece en cuanto el enunciado dice "todos": la división (sección 6).

### 2. El script de la sesión

Los ejemplos de las secciones 3 a 7 usan otra vez las matrículas de S9 y S13, con dos filas más que no tienen pareja: **Elena**, que todavía no ha aprobado ningún curso, y el curso **Seminario**, que nadie ha aprobado. Son las mismas que se insertaron como ejemplo en S13 (sección 5.1). El script [`S15-matriculas.sql`](S15-matriculas.sql) recrea el esquema `matriculas` con todo cargado:

```bash
# desde entorno-docker/, con el archivo copiado en postgres/scripts/
docker compose exec postgres psql -U curso -d curso -f /scripts/S15-matriculas.sql
docker compose exec postgres psql -U curso -d curso
```

```sql
curso=# SET search_path TO matriculas;
```

| Estudiante | Programa | Aprobó (nota) |
|---|---|---|
| Ana (2610001) | Ingeniería de Sistemas (3743) | Bases de Datos (4.5), Programación I (3.8), Estadística I (3.2) |
| Bruno (2610002) | Ingeniería de Sistemas (3743) | Programación I (4.0) |
| Carla (2610003) | Estadística (3752) | Estadística I (4.7) |
| Diego (2610004) | Ingeniería de Sistemas (3743) | Bases de Datos (3.0), Programación I (3.5) |
| **Elena (2610005)** | Estadística (3752) | *(ninguno)* |

Los cursos son `750006C` Bases de Datos (4 créditos), `750001C` Programación I (3), `760001C` Estadística I (3) y **`750090C` Seminario (1)**, que no tiene filas en `aprobo`.

La sección 8 usa un segundo script, [`S15-reportes-demo.sql`](S15-reportes-demo.sql), con un esquema mínimo de biblioteca.

### 3. Joins externos: conservar las filas sin pareja

#### 3.1 El problema

El `JOIN` de S13 (en rigor, `INNER JOIN`) solo devuelve las filas que **encontraron pareja**:

```sql
SELECT e.nombre, a.cod_curso, a.nota
FROM   estudiante e
JOIN   aprobo a ON a.cod_est = e.cod_est;      -- 7 filas: Elena no aparece
```

Para un listado de "cada estudiante con sus cursos aprobados", que Elena desaparezca es un error: existe, solo que no tiene cursos. Si la consulta fuera la base de un reporte de "estudiantes sin avance", sería justo la fila que se buscaba.

#### 3.2 `LEFT JOIN`

Un **join externo izquierdo** conserva **todas** las filas de la tabla de la izquierda; las que no encuentran pareja salen con `NULL` en las columnas de la derecha:

```sql
SELECT e.nombre, a.cod_curso, a.nota
FROM   estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
ORDER BY e.nombre, a.cod_curso;
```

| nombre | cod_curso | nota |
|---|---|---|
| Ana | 750001C | 3.8 |
| Ana | 750006C | 4.5 |
| Ana | 760001C | 3.2 |
| Bruno | 750001C | 4.0 |
| Carla | 760001C | 4.7 |
| Diego | 750001C | 3.5 |
| Diego | 750006C | 3.0 |
| Elena | *NULL* | *NULL* |

"Izquierda" es simplemente la tabla que se escribe antes del `LEFT JOIN`. Las tres variantes:

| Join | Conserva sin pareja… | Ejemplo con estas tablas |
|---|---|---|
| `A LEFT JOIN B` | las filas de A | Elena, con `NULL` en las columnas de `aprobo` |
| `A RIGHT JOIN B` | las filas de B | `aprobo a RIGHT JOIN curso c`: Seminario, con `NULL` en las de `aprobo` |
| `A FULL JOIN B` | las de ambos lados | Si se combinan estudiantes y cursos a través de `aprobo`, aparecerían Elena y Seminario |

`A RIGHT JOIN B` es lo mismo que `B LEFT JOIN A`. En la práctica casi todo el mundo escribe solo `LEFT JOIN` y ordena las tablas para que la que se quiere conservar quede a la izquierda; así se lee igual que una frase ("todos los estudiantes, con sus cursos si los tienen"). `FULL JOIN` se usa poco: sirve, por ejemplo, para comparar dos listas y ver qué sobra de cada lado.

Los joins externos son los que S9 mencionó y dejó para M4: en el álgebra se escriben ⟕, ⟖ y ⟗, y no son operadores básicos.

#### 3.3 "Los que no tienen": el anti-join

Si las filas sin pareja salen con `NULL` a la derecha, basta con quedarse con esas:

```sql
SELECT e.nombre
FROM   estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
WHERE  a.cod_est IS NULL;                      -- Elena
```

La columna que se revisa con `IS NULL` debe ser una que **nunca** sea `NULL` cuando sí hay pareja: lo más seguro es una columna de la PK o de la condición del join (aquí `a.cod_est`). Revisar `a.nota IS NULL` funcionaría hoy porque `nota` es `NOT NULL`, pero se rompe si algún día deja de serlo. La misma pregunta se puede escribir con `NOT EXISTS` (sección 5.4), y PostgreSQL ejecuta las dos de la misma forma.

#### 3.4 La trampa: filtrar en el `ON` o en el `WHERE`

*Cada estudiante con su nota de Bases de Datos, si la tiene.* Estas dos consultas parecen iguales y no lo son:

```sql
-- (a) filtro en el WHERE
SELECT e.nombre, a.nota
FROM   estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
WHERE  a.cod_curso = '750006C';               -- Ana 4.5, Diego 3.0

-- (b) filtro en el ON
SELECT e.nombre, a.nota
FROM   estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est AND a.cod_curso = '750006C';
                                              -- Ana 4.5, Bruno NULL, Carla NULL, Diego 3.0, Elena NULL
```

En (a), el `LEFT JOIN` conserva a Bruno, Carla y Elena con `NULL`, pero después el `WHERE` pregunta `NULL = '750006C'`, que es desconocido (S13, sección 6.4), y los descarta: el join externo se volvió interno sin avisar. En (b), la condición sobre el curso es parte de **cómo se busca la pareja**, así que quien no aprobó Bases de Datos se conserva con `NULL`. La regla: en un `LEFT JOIN`, las condiciones sobre la tabla de la derecha van en el `ON`; en el `WHERE` solo van las condiciones sobre la tabla que se quiere conservar.

### 4. Agregación: `GROUP BY` y `HAVING`

#### 4.1 Funciones de agregación

Una función de agregación toma **muchas filas** y devuelve **un valor**:

```sql
SELECT count(*), count(DISTINCT cod_est), round(avg(nota), 2), min(nota), max(nota), sum(nota)
FROM   aprobo;
```

| count | count | round | min | max | sum |
|---|---|---|---|---|---|
| 7 | 4 | 3.81 | 3.0 | 4.7 | 26.7 |

| Función | Devuelve | Con `NULL` |
|---|---|---|
| `count(*)` | Número de filas | Cuenta todas las filas, tengan lo que tengan |
| `count(col)` | Número de filas donde `col` no es `NULL` | Ignora los `NULL` |
| `count(DISTINCT col)` | Número de valores distintos de `col` | Ignora los `NULL` |
| `sum(col)`, `avg(col)` | Suma y promedio | Ignoran los `NULL`; sobre cero filas devuelven `NULL`, no 0 |
| `min(col)`, `max(col)` | Menor y mayor valor | Ignoran los `NULL`; sirven también para fechas y texto |

`avg` de PostgreSQL devuelve muchos decimales (3.8142857…); `round(x, 2)` los recorta para mostrar.

#### 4.2 `GROUP BY`: un resultado por grupo

*Cuántos cursos aprobó cada estudiante y con qué promedio:*

```sql
SELECT   cod_est, count(*) AS cursos, round(avg(nota), 2) AS promedio
FROM     aprobo
GROUP BY cod_est
ORDER BY cod_est;
```

| cod_est | cursos | promedio |
|---|---|---|
| 2610001 | 3 | 3.83 |
| 2610002 | 1 | 4.00 |
| 2610003 | 1 | 4.70 |
| 2610004 | 2 | 3.25 |

`GROUP BY` parte las filas en grupos con el mismo valor de las columnas indicadas, y cada agregado se calcula **por grupo**. De cada grupo sale una sola fila de resultado.

De ahí la regla que más errores produce: **en el `SELECT` de una consulta agrupada solo puede ir lo que tiene un valor único por grupo**, es decir, las columnas del `GROUP BY` y los agregados. Esta consulta falla:

```sql
SELECT e.nombre, a.cod_curso, count(*)
FROM   estudiante e JOIN aprobo a ON a.cod_est = e.cod_est
GROUP BY e.nombre;
```

```
ERROR:  column "a.cod_curso" must appear in the GROUP BY clause or be used in an aggregate function
```

Ana tiene tres cursos: ¿cuál de los tres `cod_curso` mostraría en su única fila? PostgreSQL no adivina. (MySQL en algunos modos sí lo hace, y muestra uno cualquiera: es una fuente clásica de reportes equivocados.)

Para mostrar el nombre en vez del código se agrupa por la clave **y** el nombre. Agrupar solo por `e.nombre` sería un error de otro tipo: dos estudiantes que se llamen igual quedarían sumados en un mismo grupo.

```sql
SELECT   e.nombre, count(*) AS cursos, sum(c.creditos) AS creditos
FROM     estudiante e
JOIN     aprobo a ON a.cod_est   = e.cod_est
JOIN     curso c  ON c.cod_curso = a.cod_curso
GROUP BY e.cod_est, e.nombre
ORDER BY creditos DESC;
```

| nombre | cursos | creditos |
|---|---|---|
| Ana | 3 | 10 |
| Diego | 2 | 7 |
| Bruno | 1 | 3 |
| Carla | 1 | 3 |

(PostgreSQL acepta también `GROUP BY e.cod_est` solo, porque sabe que `cod_est` es la PK y el nombre depende de ella; es la dependencia funcional de M5. Escribir las dos columnas funciona en cualquier motor.)

#### 4.3 `HAVING`: filtrar grupos

*Estudiantes con al menos dos cursos aprobados, y su promedio:*

```sql
SELECT   e.nombre, round(avg(a.nota), 2) AS promedio
FROM     estudiante e
JOIN     aprobo a ON a.cod_est = e.cod_est
GROUP BY e.cod_est, e.nombre
HAVING   count(*) >= 2
ORDER BY promedio DESC;                       -- Ana 3.83, Diego 3.25
```

`WHERE` y `HAVING` filtran cosas distintas:

| | `WHERE` | `HAVING` |
|---|---|---|
| Filtra | **filas**, antes de agrupar | **grupos**, después de agrupar |
| Puede usar agregados | No (todavía no se han calculado) | Sí |
| Ejemplo | `WHERE nota >= 3.5` | `HAVING count(*) >= 2` |

Se pueden usar juntos. *Cursos con al menos dos estudiantes que los aprobaron con 3.5 o más:*

```sql
SELECT   cod_curso, count(*)
FROM     aprobo
WHERE    nota >= 3.5          -- primero se descartan las notas bajas
GROUP BY cod_curso
HAVING   count(*) >= 2;       -- luego los cursos con pocas filas: queda 750001C (3)
```

`WHERE count(*) >= 2` es un error de sintaxis. Al revés, una condición que no usa agregados (`HAVING cod_curso = '750001C'`) funciona en el `HAVING`, pero va en el `WHERE`: descarta las filas antes y le ahorra trabajo al motor.

#### 4.4 El orden completo de evaluación

S13 (sección 6.1) dejó pendiente dónde entran `GROUP BY` y `HAVING`:

| Se escribe | Se evalúa | Qué hace |
|---|---|---|
| `SELECT …` | 5 | Arma las columnas del resultado y les pone nombre (los alias) |
| `FROM … JOIN …` | 1 | Arma las filas combinando tablas |
| `WHERE …` | 2 | Descarta filas |
| `GROUP BY …` | 3 | Agrupa las filas que quedaron y calcula los agregados de cada grupo |
| `HAVING …` | 4 | Descarta grupos |
| `ORDER BY …` | 6 | Ordena el resultado |
| `LIMIT` / `FETCH FIRST` | 7 | Corta |

Las mismas reglas de S13 se extienden: un alias del `SELECT` no existe todavía en el `WHERE` ni en el `HAVING` (por eso se repite `count(*)` en el `HAVING` en vez de usar el alias), y sí existe en el `ORDER BY`. Según el estándar tampoco existe en el `GROUP BY`, aunque PostgreSQL lo acepta ahí como extensión.

Dos precisiones sobre esta tabla:

- **Es un orden lógico, no físico.** Dice qué nombres y qué valores existen en cada cláusula, no el orden en que el motor hace el trabajo: el optimizador puede reordenar todo mientras el resultado sea el mismo.
- **Los agregados se calculan con el grupo, no en el `SELECT`.** Al formar los grupos (paso 3), cualquier agregado sobre las filas del grupo ya se puede usar. Por eso el `HAVING` acepta agregados que **no** aparecen en el `SELECT`: `SELECT cod_est, round(avg(nota), 2) FROM aprobo GROUP BY cod_est HAVING max(nota) >= 4.5` funciona (Ana y Carla) aunque el `max` no se muestre. Lo que el `HAVING` no puede usar es el **nombre** que el `SELECT` le pone a una columna: `HAVING cursos >= 2` da `column "cursos" does not exist`; hay que repetir la expresión (`HAVING count(*) >= 2`).

En otros motores esto varía: MySQL y SQLite aceptan alias del `SELECT` también en el `HAVING`. Son extensiones al estándar, como la de PostgreSQL en el `GROUP BY`; repetir la expresión funciona en todos.

#### 4.5 Contar ceros: agregación con `LEFT JOIN`

*Cuántos cursos aprobó cada estudiante, incluidos los que no aprobaron ninguno.* Hace falta el `LEFT JOIN` para que Elena aparezca, y hace falta contar la columna correcta:

```sql
SELECT   e.nombre, count(*) AS mal, count(a.cod_curso) AS bien
FROM     estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
GROUP BY e.cod_est, e.nombre
ORDER BY e.nombre;
```

| nombre | mal | bien |
|---|---|---|
| Ana | 3 | 3 |
| Bruno | 1 | 1 |
| Carla | 1 | 1 |
| Diego | 2 | 2 |
| Elena | **1** | **0** |

Elena tiene una fila en el resultado del join (la que el `LEFT JOIN` conservó con `NULL`), así que `count(*)` dice 1. `count(a.cod_curso)` ignora el `NULL` y dice 0, que es la respuesta correcta. Esta combinación, `LEFT JOIN` + `count(columna de la derecha)`, es exactamente la del reporte de libros más prestados (sección 8).

### 5. Subconsultas

Una **subconsulta** es un `SELECT` entre paréntesis dentro de otra consulta. Según lo que devuelva, se usa en lugares distintos.

#### 5.1 Subconsulta escalar: un solo valor

*Notas por encima del promedio general:*

```sql
SELECT cod_est, cod_curso, nota
FROM   aprobo
WHERE  nota > (SELECT avg(nota) FROM aprobo)   -- 3.81…
ORDER BY nota DESC;                             -- 4.7, 4.5, 4.0
```

La subconsulta devuelve una fila y una columna, así que se puede comparar con `>` como si fuera un número. Si devolviera más de una fila, PostgreSQL daría error (`more than one row returned by a subquery used as an expression`). No se puede escribir `WHERE nota > avg(nota)`: el `WHERE` va antes de cualquier agregación (sección 4.4).

#### 5.2 `IN` y `NOT IN`: pertenencia a una lista

```sql
SELECT nombre FROM estudiante
WHERE  cod_est IN (SELECT cod_est FROM aprobo WHERE cod_curso = '750006C');      -- Ana, Diego

SELECT nombre FROM estudiante
WHERE  cod_est NOT IN (SELECT cod_est FROM aprobo WHERE cod_curso = '750006C');  -- Bruno, Carla, Elena
```

La subconsulta devuelve una columna con muchas filas, y `IN` pregunta si el valor está en esa lista. Es la versión con subconsulta del `IN (lista)` de S13.

#### 5.3 La trampa de `NOT IN` con `NULL`

```sql
SELECT nombre FROM estudiante WHERE cod_prog NOT IN (3743);         -- Carla, Elena
SELECT nombre FROM estudiante WHERE cod_prog NOT IN (3743, NULL);   -- 0 filas
```

`x NOT IN (3743, NULL)` significa `x <> 3743 AND x <> NULL`, y `x <> NULL` es desconocido para cualquier `x`. El `AND` de algo con desconocido nunca llega a ser verdadero, y el `WHERE` descarta todas las filas. Nadie escribe `NULL` a mano en la lista, pero sí pasa con una subconsulta: si la columna que devuelve puede tener un solo `NULL`, el `NOT IN` devuelve vacío sin dar ningún error. La regla práctica es **preferir `NOT EXISTS` a `NOT IN` con subconsultas**, porque `NOT EXISTS` no tiene este problema. (`IN`, sin el `NOT`, no tiene la trampa.)

#### 5.4 `EXISTS` y `NOT EXISTS`: subconsultas correlacionadas

```sql
-- estudiantes con al menos una nota de 4.5 o más
SELECT e.nombre
FROM   estudiante e
WHERE  EXISTS (SELECT 1
               FROM   aprobo a
               WHERE  a.cod_est = e.cod_est      -- ← usa la fila de afuera
                 AND  a.nota >= 4.5);            -- Ana, Carla

-- cursos que nadie ha aprobado
SELECT c.nombre_curso
FROM   curso c
WHERE  NOT EXISTS (SELECT 1 FROM aprobo a WHERE a.cod_curso = c.cod_curso);   -- Seminario
```

`EXISTS (subconsulta)` es verdadero si la subconsulta devuelve **al menos una fila**; no importa qué columnas, por eso se escribe `SELECT 1`. La subconsulta es **correlacionada**: menciona `e.cod_est`, una columna de la consulta de afuera, así que conceptualmente se evalúa una vez por cada estudiante (el optimizador, en la práctica, la convierte en un join).

`EXISTS` es la forma más directa de preguntar "¿tiene al menos un…?", y es la del reporte de lectores morosos: un lector es moroso si **existe** un préstamo suyo vencido y sin devolver (sección 8).

Una curiosidad que conviene tener presente: `NOT EXISTS` es verdadero cuando no hay filas, y eso incluye el caso en que no hay nada que revisar. *Cursos donde nadie sacó menos de 3.5:*

```sql
SELECT c.nombre_curso FROM curso c
WHERE  NOT EXISTS (SELECT 1 FROM aprobo a
                   WHERE a.cod_curso = c.cod_curso AND a.nota < 3.5);   -- Programación I, Seminario
```

Seminario aparece porque nadie lo ha aprobado, así que tampoco hay nadie con menos de 3.5. Lógicamente es correcto ("todas las notas de Seminario son ≥ 3.5" es verdadero si no hay notas); si el reporte no lo quiere, hay que pedir además que exista al menos una nota.

#### 5.5 Subconsultas en el `FROM` y `WITH`

Una subconsulta que devuelve una tabla completa se puede usar como si fuera una tabla más, en el `FROM` (con un alias obligatorio):

```sql
SELECT max(promedio)
FROM   (SELECT cod_est, avg(nota) AS promedio FROM aprobo GROUP BY cod_est) AS t;   -- 4.70
```

Cuando la misma subconsulta se necesita dos veces, o la consulta se vuelve difícil de leer, se le da nombre con `WITH` (una *expresión de tabla común*, CTE). *El o los estudiantes con el mejor promedio:*

```sql
WITH promedios AS (
    SELECT cod_est, round(avg(nota), 2) AS promedio
    FROM   aprobo
    GROUP BY cod_est
)
SELECT e.nombre, p.promedio
FROM   promedios p
JOIN   estudiante e ON e.cod_est = p.cod_est
WHERE  p.promedio = (SELECT max(promedio) FROM promedios);   -- Carla 4.70
```

Se lee de arriba abajo: primero se define `promedios`, después se usa dos veces. Esta forma, "el máximo, con empates", es la del reporte de lectores que más leen (sección 8). Se prefiere a `ORDER BY promedio DESC LIMIT 1`, que devuelve **una** fila aunque haya dos estudiantes empatados en el primer lugar.

### 6. La división con `NOT EXISTS` doble

En S9 (sección 6.6) se resolvió con ÷ esta consulta: *¿qué estudiantes aprobaron **todos** los cursos de 3 créditos?* La respuesta era Ana. SQL no tiene operador de división, así que hay que reformular la pregunta. "Aprobó todos los cursos de 3 créditos" es lo mismo que **"no existe un curso de 3 créditos que no haya aprobado"**:

```sql
SELECT e.nombre
FROM   estudiante e
WHERE  NOT EXISTS (                              -- no existe…
         SELECT 1 FROM curso c
         WHERE  c.creditos = 3                   -- …un curso de 3 créditos…
           AND  NOT EXISTS (                     -- …que no haya aprobado
                  SELECT 1 FROM aprobo a
                  WHERE  a.cod_est   = e.cod_est
                    AND  a.cod_curso = c.cod_curso));
                                                 -- Ana
```

Para leerla, conviene seguirla con un estudiante concreto:

- **Ana.** Para Programación I y para Estadística I existe su fila en `aprobo`, así que el `NOT EXISTS` de adentro es falso para los dos cursos; la subconsulta del medio no encuentra ningún curso y el `NOT EXISTS` de afuera es verdadero. Ana sale.
- **Bruno.** Para Estadística I no hay fila en `aprobo`: el `NOT EXISTS` de adentro es verdadero, la subconsulta del medio encuentra Estadística I y el `NOT EXISTS` de afuera es falso. Bruno no sale. Lo mismo pasa con Carla (le falta Programación I), Diego (Estadística I) y Elena (los dos).

La consulta del medio produce, para cada estudiante, **la lista de lo que le falta**; el `NOT EXISTS` de afuera se queda con los que no les falta nada. Las piezas siempre son las mismas: la tabla de candidatos afuera (`estudiante`), el divisor en el medio (`curso` filtrado) y la tabla que los relaciona adentro (`aprobo`). El libro guía escribe la parte de adentro con `EXCEPT` en vez del segundo `NOT EXISTS`; es la misma idea.

#### 6.1 La alternativa con conteo

También se puede razonar contando: un estudiante aprobó todos los cursos de 3 créditos si el número de cursos de 3 créditos que aprobó es igual al número de cursos de 3 créditos que existen.

```sql
SELECT   e.nombre
FROM     estudiante e
JOIN     aprobo a ON a.cod_est   = e.cod_est
JOIN     curso c  ON c.cod_curso = a.cod_curso
WHERE    c.creditos = 3
GROUP BY e.cod_est, e.nombre
HAVING   count(*) = (SELECT count(*) FROM curso WHERE creditos = 3);   -- Ana
```

Es más fácil de escribir, pero tiene dos condiciones para que sea correcta: no puede haber filas repetidas en el join (aquí la PK de `aprobo` lo garantiza; si no, `count(DISTINCT c.cod_curso)`) y el divisor no puede estar vacío.

#### 6.2 El caso del divisor vacío

*¿Qué estudiantes aprobaron todos los cursos de 5 créditos?* No hay cursos de 5 créditos. La versión con `NOT EXISTS` devuelve **los cinco estudiantes** (no existe un curso de 5 créditos que les falte, porque no existe ninguno); la versión con conteo devuelve **cero** (nadie tiene filas que agrupar). Lógicamente, la primera tiene razón: "todos los elementos de un conjunto vacío cumplen X" es verdadero, igual que el ejemplo de Seminario en la sección 5.4. En la práctica, si el resultado de la primera no tiene sentido para el negocio, se agrega una condición que exija que el divisor no esté vacío. Lo importante es saber que las dos versiones **no son equivalentes** en ese borde.

### 7. El cálculo relacional, en una página

El álgebra (S9) dice **cómo** obtener el resultado: qué operadores aplicar y en qué orden. El **cálculo relacional**, propuesto también por Codd, dice **qué** propiedad cumplen las filas del resultado, con la notación de la lógica de predicados. SQL heredó del cálculo su estilo declarativo, y de ahí sale la forma de las subconsultas con `EXISTS`.

#### 7.1 Cálculo relacional de tuplas

Una consulta tiene la forma { *t* | *P*(*t*) }: "las tuplas *t* que cumplen la condición *P*". Las variables recorren las filas de una relación.

| Cálculo de tuplas | Se lee | SQL |
|---|---|---|
| { e \| e ∈ Estudiante ∧ e.cod_prog = 3743 } | Los estudiantes cuyo programa es 3743 | `SELECT * FROM estudiante e WHERE e.cod_prog = 3743` |
| { e.nombre \| e ∈ Estudiante ∧ ∃ a ∈ Aprobo (a.cod_est = e.cod_est ∧ a.cod_curso = '750006C') } | Los nombres de los estudiantes para los que **existe** una fila de `aprobo` con Bases de Datos | `SELECT e.nombre FROM estudiante e WHERE EXISTS (SELECT 1 FROM aprobo a WHERE a.cod_est = e.cod_est AND a.cod_curso = '750006C')` |

El cuantificador existencial ∃ es, literalmente, el `EXISTS` de SQL.

#### 7.2 La división: el "para todo"

En el cálculo, "todos" se escribe con el cuantificador universal ∀ y una implicación:

{ e.nombre | e ∈ Estudiante ∧ ∀ c ∈ Curso ( c.creditos = 3 ⇒ ∃ a ∈ Aprobo (a.cod_est = e.cod_est ∧ a.cod_curso = c.cod_curso) ) }

"Para todo curso *c*, si *c* tiene 3 créditos, entonces existe una fila de `aprobo` de *e* con *c*." SQL no tiene `FOR ALL`, pero la lógica da dos equivalencias:

- ∀ c ( P ⇒ Q ) ≡ ¬∃ c ( P ∧ ¬Q ): "todo curso que cumple P cumple Q" es lo mismo que "no existe un curso que cumpla P y no cumpla Q".
- ¬∃ es `NOT EXISTS`.

Al aplicarlas queda ¬∃ c ( c.creditos = 3 ∧ ¬∃ a (…) ), que se traduce palabra por palabra en el `NOT EXISTS` doble de la sección 6. Esa es la razón de su forma.

#### 7.3 Cálculo de dominios y equivalencia

En el **cálculo relacional de dominios**, las variables recorren **valores** de las columnas, no filas enteras: { ⟨n⟩ | ∃ c, p ( ⟨c, n, p⟩ ∈ Estudiante ∧ p = 3743 ) } son los nombres *n* de los estudiantes del programa 3743. Es la base de QBE (*Query By Example*), el estilo de "llenar una cuadrícula con condiciones" que usan los diseñadores de consultas de Access o de LibreOffice Base.

Codd demostró que el álgebra relacional y el cálculo relacional (en su versión **segura**, la que solo puede devolver valores que están en la base: una consulta como { t | ¬(t ∈ Estudiante) } describe infinitas tuplas y no se permite) pueden expresar exactamente las mismas consultas. A un lenguaje que alcanza esa capacidad se le llama **relacionalmente completo**, y SQL lo es (y va más allá, con la agregación, que ni el álgebra ni el cálculo básicos tienen).

### 8. Los cuatro reportes del proyecto, sobre un esquema mínimo

Igual que en S14, usaremos un esquema de demostración (`reportes_demo`) con las consultas resueltas; cada grupo las reescribe sobre **su** esquema en S16. El script [`S15-reportes-demo.sql`](S15-reportes-demo.sql) crea tres tablas:

```
libro    (isbn PK, titulo, autor, categoria)
lector   (documento PK, nombres, apellidos, correo, telefono)
prestamo (id PK, isbn → libro, documento → lector,
          fecha_prestamo, fecha_esperada, fecha_devolucion)   -- devolución NULL = préstamo abierto
```

carga 9 libros y 6 lectores de los CSV semilla y 15 préstamos, cada uno pensado para probar un caso: un libro que nadie ha prestado, dos lectores empatados en libros leídos, un lector con tres préstamos abiertos y ninguno devuelto, un préstamo devuelto tarde (fue mora, ya no lo es), uno que vence hoy (todavía no es mora) y un lector sin préstamos. Las fechas se calculan a partir de `CURRENT_DATE`, así que los reportes de mora dan lo mismo cualquier día que se corra el script. Al terminar, el script imprime los cuatro reportes:

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/S15-reportes-demo.sql
```

#### 8.1 Reporte 1: los 20 libros más prestados

```sql
SELECT   l.titulo, count(p.id) AS prestamos
FROM     libro l
LEFT JOIN prestamo p ON p.isbn = l.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;
```

Con 9 libros, el top 20 los muestra todos; para ver el efecto, el script pide los 3 primeros (`FETCH FIRST 3 ROWS WITH TIES`) y devuelve **4** filas: Cien años de soledad (4), Rayuela (3), Ficciones (2) y Pedro Páramo (2). Hay un empate en el tercer puesto, y `WITH TIES` incluye a todos los empatados con la última fila. `LIMIT 3` habría dejado por fuera a uno de los dos, escogido al azar. Si se quiere además un orden fijo entre los empatados, no sirve agregar `l.titulo` al `ORDER BY`, porque `WITH TIES` compararía también el título y el empate desaparecería; se envuelve la consulta en una subconsulta y se ordena afuera.

El `LEFT JOIN` con `count(p.id)` (sección 4.5) hace que El Aleph, que nadie ha prestado, aparezca con 0. Con 20 o más libros prestados no cambia nada, pero en la base recién cargada de un grupo puede ser la diferencia entre un reporte vacío y uno que muestra el catálogo.

#### 8.2 Reporte 2: el o los lectores que más libros han leído

```sql
WITH leidos AS (
    SELECT   documento, count(*) AS devueltos
    FROM     prestamo
    WHERE    fecha_devolucion IS NOT NULL       -- solo préstamos completados
    GROUP BY documento
)
SELECT r.nombres, r.apellidos, x.devueltos
FROM   leidos x
JOIN   lector r ON r.documento = x.documento
WHERE  x.devueltos = (SELECT max(devueltos) FROM leidos)
ORDER BY r.apellidos;                           -- Mariana 3, Santiago 3
```

Dos decisiones del documento del proyecto se ven aquí: "el **o los**" exige manejar empates (por eso `= max(…)` y no `LIMIT 1`), y "libros leídos" son **préstamos devueltos** (sección 3.2 del proyecto), por eso el `WHERE`. Juan David tiene tantos préstamos como los ganadores (tres), pero ninguno devuelto: sin el filtro saldría empatado con ellos, y el reporte premiaría a quien retiene libros.

#### 8.3 Reporte 3: lectores morosos

```sql
SELECT r.documento, r.nombres, r.apellidos
FROM   lector r
WHERE  EXISTS (SELECT 1
               FROM   prestamo p
               WHERE  p.documento = r.documento
                 AND  p.fecha_devolucion IS NULL          -- no devuelto
                 AND  p.fecha_esperada < CURRENT_DATE)    -- y ya vencido
ORDER BY r.apellidos;                     -- Camila, Valentina, Juan David
```

Un lector aparece **una vez** aunque tenga varios préstamos en mora (Juan David tiene dos). Con un `JOIN` en lugar del `EXISTS` aparecería repetido y habría que agregar `DISTINCT`. Santiago no sale: devolvió tarde el Quijote, pero ya lo devolvió. Valentina sí, por *La sombra del viento*, aunque su otro préstamo abierto todavía esté a tiempo.

#### 8.4 Reporte 4: préstamos en mora (la lista de notificación)

```sql
SELECT r.nombres || ' ' || r.apellidos  AS lector,
       r.correo, r.telefono,
       l.titulo,
       p.fecha_esperada,
       CURRENT_DATE - p.fecha_esperada  AS dias_mora
FROM   prestamo p
JOIN   lector r ON r.documento = p.documento
JOIN   libro  l ON l.isbn      = p.isbn
WHERE  p.fecha_devolucion IS NULL
  AND  p.fecha_esperada < CURRENT_DATE
ORDER BY dias_mora DESC;
```

| lector | titulo | dias_mora |
|---|---|---|
| Juan David Martínez Ruiz | Ficciones | 26 |
| Valentina López Díaz | La sombra del viento | 16 |
| Juan David Martínez Ruiz | Cien años de soledad | 6 |
| Camila Hernández Torres | Pedro Páramo | 2 |

(La tabla omite las columnas de correo, teléfono y fecha.) Aquí la unidad es el **préstamo**, no el lector: Juan David sale dos veces, una por libro, que es lo que necesita la lista con el botón "Enviar notificación" del proyecto. La condición es la misma del reporte 3; cambia lo que se muestra. Restar dos `date` en PostgreSQL da un número entero de días. Rayuela, que Juan David debe devolver hoy, no aparece: con `<` estricto, un préstamo que vence hoy todavía no está en mora. Si un grupo decide lo contrario, cambia a `<=` y lo documenta.

#### 8.5 Lo que cambia en el esquema de cada grupo

El esquema de demostración es deliberadamente plano. Al pasar las consultas al esquema propio (S16), lo que más cambia es:

- **Copias físicas.** Si el préstamo apunta a un `ejemplar` y no al `libro`, el reporte 1 necesita un join más (`prestamo → ejemplar → libro`) y debe agrupar por el **libro**: "los libros más prestados" son títulos, no copias.
- **Usuarios y perfiles.** Si el lector es un perfil de una tabla `usuario` (la opción 2 de S11), el nombre, el correo y el teléfono pueden estar en `usuario` y hace falta ese join.
- **Estado del préstamo.** Si el esquema tiene una columna `estado` (`'activo'`, `'devuelto'`, `'en mora'`), hay que decidir si los reportes confían en ella o calculan la mora con las fechas. Mientras no exista el trigger del Hito 4 que la mantenga al día, una columna `estado = 'en mora'` no se actualiza sola cuando pasa la fecha; calcular con fechas es lo seguro.
- **Plazo.** Si el esquema guarda solo la fecha de préstamo y el plazo vive en una regla (14 días), la condición pasa a ser `p.fecha_prestamo + 14 < CURRENT_DATE`.

### 9. Resumen

| Necesidad | SQL | Ojo con |
|---|---|---|
| Conservar las filas sin pareja | `LEFT JOIN` | Las condiciones sobre la tabla de la derecha van en el `ON`, no en el `WHERE`. |
| "Los que no tienen…" | `LEFT JOIN … WHERE b.pk IS NULL` o `NOT EXISTS` | Revisar `IS NULL` sobre una columna que nunca sea `NULL` cuando hay pareja. |
| Un valor por grupo | `GROUP BY` + agregados | En el `SELECT` solo van columnas del `GROUP BY` y agregados. |
| Filtrar grupos | `HAVING` | `WHERE` filtra filas antes de agrupar; no acepta agregados. |
| Contar incluyendo ceros | `LEFT JOIN` + `count(b.col)` | `count(*)` cuenta 1 para la fila sin pareja. |
| Comparar con un valor calculado | Subconsulta escalar | Debe devolver una sola fila. |
| "Tiene al menos un…" | `EXISTS` | No repite filas, a diferencia de un `JOIN`. |
| "No está en…" | `NOT EXISTS` | `NOT IN` devuelve vacío si la subconsulta trae un `NULL`. |
| El máximo, con empates | `WITH` + `= (SELECT max(…))`, o `FETCH FIRST n ROWS WITH TIES` | `LIMIT 1` descarta los empatados. |
| "Los que … todos …" (÷) | `NOT EXISTS` doble | Con el divisor vacío, devuelve a todos; la versión con conteo, a nadie. |

| Álgebra / cálculo | SQL |
|---|---|
| ⟕, ⟖, ⟗ (joins externos) | `LEFT JOIN`, `RIGHT JOIN`, `FULL JOIN` |
| ∃ | `EXISTS` |
| ¬∃ | `NOT EXISTS` |
| ∀ c (P ⇒ Q) ≡ ¬∃ c (P ∧ ¬Q) | `NOT EXISTS (… P AND NOT EXISTS (… Q …))` |
| ÷ | `NOT EXISTS` doble |

En **S16** (laboratorio) se practica todo esto con un conjunto de ejercicios sobre un esquema nuevo, y cada grupo escribe los cuatro reportes sobre su propio esquema para cerrar el Hito 2.

## Lectura del libro

**Silberschatz, Korth, Sudarshan, *Fundamentos de Bases de Datos*, 6ª ed.**

- Capítulo 3, "Introducción a SQL": secciones 3.7 (funciones de agregación: `GROUP BY`, `HAVING`, agregados con `NULL`) y 3.8 (subconsultas anidadas: pertenencia, comparación de conjuntos, `EXISTS` y la división con `NOT EXISTS … EXCEPT`, subconsultas en el `FROM`, `WITH`, subconsultas escalares).
- Capítulo 4, "SQL intermedio": sección 4.1 (expresiones de join: condiciones de join y joins externos).
- Capítulo 6, "Lenguajes formales de consulta relacional": secciones 6.2 (cálculo relacional de tuplas: ejemplos, seguridad de las expresiones, poder expresivo) y 6.3 (cálculo relacional de dominios), en lectura rápida.



