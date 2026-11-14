-- =====================================================================
-- CASO 1: GIMNASIO
-- Esquema original: socio (id_socio PK, nombre, plan, valor_plan, clases)
-- La queja: "Le pedí al sistema cuántos socios hay en Yoga para abrir otro
--   grupo y me dijo 2, pero yo sé que son 3. Y en Spinning me dijo 3, cuando
--   son 2."
-- =====================================================================
SET search_path TO gimnasio;

-- ======================================
-- (a) DIAGNÓSTICO
-- ======================================
-- Dependencias funcionales (con la regla que las justifica):
--   id_socio -> nombre, plan, valor_plan   (id_socio es la PK)
--   plan     -> valor_plan                 (regla: cada plan tiene un valor fijo)
--
-- Problema principal (1FN): la columna 'clases' almacena una lista de valores
--   separados por punto y coma (;). Esto obliga a usar LIKE, generando falsos
--   positivos ('Spinning avanzado' cuenta como 'Spinning') y falsos negativos
--   por mayúsculas/minúsculas ('yoga' vs 'Yoga'). Es la causa de la queja.
--
-- Problema secundario (3FN): dependencia transitiva id_socio -> plan -> valor_plan.
--   El valor del plan depende del tipo de plan, no directamente del socio, lo que
--   genera redundancia (90000 se repite en cada socio Mensual) y anomalías de
--   actualización (subir el plan Mensual obliga a cambiar todas sus filas).
--
-- Otro síntoma de no estar en 1FN: como la lista es texto libre, la misma clase
--   aparece escrita de varias formas ('Yoga', ' Yoga ', 'yoga') y nada lo impide.

-- ======================================
-- (b) EVIDENCIA
-- ======================================

-- 1. Ver todos los datos crudos para detectar suciedad (espacios, mayúsculas)
SELECT * FROM socio;
-- Resultado: 6 socios. María Fernanda tiene 'Pilates;yoga' (minúscula),
--   Andrés tiene 'Yoga ' con espacio al final y Sofía no tiene clases (NULL).

-- 2. Demostrar el error de la queja con LIKE (subestima Yoga y sobreestima Spinning)
SELECT count(*) AS yoga_con_like FROM socio WHERE clases LIKE '%Yoga%';
-- Resultado: 2. Deberían ser 3: falta María Fernanda, que escribió 'yoga'.

SELECT count(*) AS yoga_case_insensitive FROM socio WHERE clases ILIKE '%Yoga%';
-- Resultado: 3. ILIKE (LIKE sin distinguir mayúsculas) corrige el caso de Yoga,
--   pero solo arregla las mayúsculas: no resuelve el problema (ver Spinning).

SELECT count(*) AS spinning_con_like FROM socio WHERE clases LIKE '%Spinning%';
-- Resultado: 3. Deberían ser 2: cuenta a Pedro, que está en 'Spinning avanzado',
--   una clase distinta que contiene la palabra 'Spinning'.

SELECT count(*) AS spinning_case_insensitive FROM socio WHERE clases ILIKE '%Spinning%';
-- Resultado: 3. Con ILIKE sigue saliendo mal: buscar dentro de un texto no
--   distingue una clase de otra cuyo nombre la contiene.

-- 3. Ver cómo está escrita realmente cada clase (los corchetes muestran los espacios)
SELECT '[' || c || ']' AS pedazo, count(*)
FROM socio s, string_to_table(s.clases, ';') AS c
GROUP BY c
ORDER BY 1;
-- Resultado: 9 pedazos, todos distintos como texto. 'Yoga' aparece de 3 formas
--   ('[Yoga]', '[ Yoga ]', '[yoga]'), 'Spinning' de 2 ('[Spinning]', '[ Spinning]')
--   y 'Funcional' de 2 ('[Funcional]', '[ Funcional]').

-- 4. Demostrar redundancia y verificar si hay contradicciones en plan -> valor_plan
SELECT plan, valor_plan, count(*) AS cantidad_socios
FROM socio
GROUP BY plan, valor_plan;
-- Resultado: Anual 850000 (2 socios), Mensual 90000 (3), Trimestral 240000 (1).
--   El valor se repite en cada socio del plan: es redundancia.

-- Si esta consulta devuelve filas, hay que decidir qué valor_plan es el correcto:
SELECT plan FROM socio GROUP BY plan HAVING count(DISTINCT valor_plan) > 1;
-- Resultado: 0 filas. Los datos no contradicen plan -> valor_plan, así que no
--   hay que decidir nada: cada plan pasa con el único valor que tiene.

-- =================================
-- (c) ESQUEMA CORREGIDO (3FN)
-- =================================
-- plan              (plan PK, valor_plan)
-- socio             (id_socio PK, nombre, plan FK -> plan)
-- clase             (id_clase PK, nombre UNIQUE)
-- inscripcion_clase (id_socio PK/FK -> socio, id_clase PK/FK -> clase)

-- ======================
-- (d) MIGRACIÓN
-- ======================
-- Conteos esperados (calculados antes de migrar):
--   plan               3  (Mensual, Trimestral, Anual)
--   clase              5  (Yoga, Spinning, Spinning Avanzado, Pilates, Funcional)
--   inscripcion_clase  9  (Laura 2, Pedro 1, María Fernanda 2, Andrés 3,
--                          Sofía 0, Tomás 1), igual a los 9 pedazos de la evidencia 3
--
-- Decisión de limpieza: initcap(trim(...)) quita los espacios y unifica
--   'Yoga', ' Yoga ' y 'yoga'. Efecto a tener en cuenta: initcap pone en
--   mayúscula cada palabra, así que 'Spinning avanzado' queda 'Spinning Avanzado'.
--
-- Ejecutar por partes: primero hasta la verificación (e); si los números
--   coinciden, el DROP COLUMN y el COMMIT. Si algo no coincide, ROLLBACK.

BEGIN;

-- 1. Crear tablas nuevas con todas las restricciones
CREATE TABLE plan (
    plan       VARCHAR(50) PRIMARY KEY,
    valor_plan INTEGER     NOT NULL CHECK (valor_plan > 0)   -- mismo tipo que en socio
);

CREATE TABLE clase (
    id_clase SERIAL PRIMARY KEY,
    nombre   VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE inscripcion_clase (
    id_socio INT NOT NULL REFERENCES socio(id_socio),
    id_clase INT NOT NULL REFERENCES clase(id_clase),
    PRIMARY KEY (id_socio, id_clase)
);

-- 2. Copiar los datos
-- Planes: uno por plan, sin repetir. Si un plan tuviera dos valores, la PK
--   fallaría aquí y la transacción se detendría.
INSERT INTO plan (plan, valor_plan)
SELECT DISTINCT plan, valor_plan
FROM socio;

-- Clases: partir la lista en filas y limpiar cada pedazo. Sofía (NULL) no
--   produce filas.
INSERT INTO clase (nombre)
SELECT DISTINCT initcap(trim(c))
FROM socio s, string_to_table(s.clases, ';') AS c;

-- Inscripciones: una fila por socio y clase, buscando la clase por su nombre limpio.
INSERT INTO inscripcion_clase (id_socio, id_clase)
SELECT s.id_socio, k.id_clase
FROM socio s, string_to_table(s.clases, ';') AS c, clase k
WHERE k.nombre = initcap(trim(c));

-- socio.plan ahora debe existir en la tabla plan
ALTER TABLE socio ADD FOREIGN KEY (plan) REFERENCES plan (plan);

-- ======================
-- (e) VERIFICACIÓN (antes de quitar las columnas viejas)
-- ======================

-- Conteos esperados frente a obtenidos
SELECT (SELECT count(*) FROM plan)              AS planes,
       (SELECT count(*) FROM clase)             AS clases,
       (SELECT count(*) FROM inscripcion_clase) AS inscripciones;
-- Esperado: 3, 5, 9. Obtenido: 3, 5, 9.

-- No se perdió ninguna inscripción: lo que había y no quedó en las tablas nuevas
SELECT s.id_socio, initcap(trim(c))
FROM socio s, string_to_table(s.clases, ';') AS c
EXCEPT
SELECT i.id_socio, k.nombre
FROM inscripcion_clase i JOIN clase k ON k.id_clase = i.id_clase;
-- Esperado: 0 filas. Obtenido: 0 filas.

-- No se inventó ninguna: lo que quedó en las tablas nuevas y no estaba antes
SELECT i.id_socio, k.nombre
FROM inscripcion_clase i JOIN clase k ON k.id_clase = i.id_clase
EXCEPT
SELECT s.id_socio, initcap(trim(c))
FROM socio s, string_to_table(s.clases, ';') AS c;
-- Esperado: 0 filas. Obtenido: 0 filas.

-- Cada socio conserva el valor de su plan
SELECT id_socio, plan, valor_plan FROM socio
EXCEPT
SELECT s.id_socio, p.plan, p.valor_plan
FROM socio s JOIN plan p ON p.plan = s.plan;
-- Esperado: 0 filas. Obtenido: 0 filas.

-- 3. Quitar lo viejo, solo después de verificar
ALTER TABLE socio DROP COLUMN valor_plan, DROP COLUMN clases;

COMMIT;

-- La queja, resuelta en el esquema nuevo
SELECT k.nombre, count(*) AS socios
FROM inscripcion_clase i JOIN clase k ON k.id_clase = i.id_clase
GROUP BY k.nombre
ORDER BY k.nombre;
-- Resultado: Funcional 2, Pilates 1, Spinning 2, Spinning Avanzado 1, Yoga 3.
--   Yoga da 3 y Spinning da 2, como decía el gimnasio.

-- ======================
-- PREGUNTA PROPIA
-- ======================
-- Después de migrar, el gimnasio quiere guardar el horario de cada clase
-- (día y hora). ¿En cuál tabla va, y por qué habría sido imposible hacerlo
-- bien con el diseño original?
--
-- Va en la tabla clase, porque el horario depende de la clase y no del socio:
--   id_clase -> dia, hora. Se guarda una sola vez por clase. Si una clase
--   tuviera varios horarios (por ejemplo, lunes y miércoles), iría en una
--   tabla aparte, horario (id_clase FK, dia, hora), con PK (id_clase, dia, hora).
--
-- Con el diseño original era imposible hacerlo bien porque la clase no existía
--   como entidad: solo era un pedazo de texto dentro de 'clases'. No había una
--   fila donde poner su horario. Una columna 'horario' en socio no sirve,
--   porque un socio tiene varias clases; habría que meter el horario dentro
--   del mismo texto, repetido en cada socio inscrito, y bastaría con que dos
--   socios lo escribieran distinto para tener horarios contradictorios de la
--   misma clase.
