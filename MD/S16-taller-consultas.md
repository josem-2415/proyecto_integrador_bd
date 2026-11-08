# S16. Laboratorio: taller de consultas complejas y los cuatro reportes del proyecto

**Módulo 4, semana 8, sesión 16 · Laboratorio sincrónico (videollamada, salas por grupo de proyecto) · *checkpoint Hito 2***

S15 cerró el lenguaje de consulta: joins externos, agregación, subconsultas y la división. Este laboratorio tiene dos partes. En la **parte A**, todos los grupos resuelven los mismos ejercicios sobre un esquema nuevo (una tienda de café) que no se parece al proyecto, para practicar sin copiar del ejemplo de S15. En la **parte B**, cada grupo escribe los cuatro reportes de la biblioteca sobre **su** esquema, con datos de prueba pensados para que los errores típicos salten a la vista. Con eso y lo de S14 queda completo el Hito 2.

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Construir una consulta de varias tablas por capas (primero el `FROM` y los joins, luego los filtros, luego la agregación), comprobando el número de filas en cada paso.
- Escoger entre `JOIN` y `LEFT JOIN`, y entre `WHERE` y `HAVING`, según lo que pida el enunciado.
- Diagnosticar y corregir una consulta con `NOT IN` que devuelve vacío por culpa de un `NULL`.
- Resolver "el o los que más…" con empates y "los que … todos …" con `NOT EXISTS` doble.
- Escribir los cuatro reportes del proyecto sobre el esquema propio y diseñar datos de prueba que demuestren que son correctos.

## Guía corta de pre-lectura (antes de la sesión)

### 1. El esquema de la parte A

El script [`S16-tienda.sql`](S16-tienda.sql) crea el esquema `tienda`, una tienda en línea de café, con cuatro tablas:

```
cliente  (id_cliente PK, nombre, ciudad, referido_por → cliente)   -- referido_por NULL: llegó solo
producto (id_producto PK, nombre, categoria, precio)               -- categoría: Grano, Molido o Accesorio
pedido   (id_pedido PK, id_cliente → cliente, fecha, estado)       -- estado: pagado, enviado o cancelado
detalle  (id_pedido → pedido, id_producto → producto,
          cantidad, precio_unitario)                               -- PK (id_pedido, id_producto)
```

Tiene 8 clientes, 10 productos, 14 pedidos (3 de ellos cancelados) y 23 líneas de detalle. Tres detalles del modelo que importan para los ejercicios:

- `referido_por` es una FK **a la misma tabla**: el cliente 2 fue recomendado por el cliente 1. Para ver el nombre de quien lo refirió hay que combinar `cliente` consigo misma, con dos alias (el ρ de S9).
- El valor de una línea de pedido es `cantidad * precio_unitario`. Se usa `precio_unitario` y no `producto.precio` porque el precio de hoy puede no ser el de la venta.
- **Un pedido cancelado no es una venta.** Salvo que el enunciado diga otra cosa, los ejercicios de ventas y compras excluyen los pedidos con `estado = 'cancelado'`.

```bash
# desde entorno-docker/, con el archivo copiado en postgres/scripts/
docker compose exec postgres psql -U curso -d curso -f /scripts/S16-tienda.sql
docker compose exec postgres psql -U curso -d curso
```

```sql
curso=# SET search_path TO tienda;
curso=# \d detalle
```

### 2. Cómo construir una consulta larga sin perderse

Las consultas de hoy tienen tres o cuatro tablas y varias cláusulas. Escribirlas de una vez y correrlas al final es la forma más lenta de llegar: si el resultado está mal, no se sabe dónde. El método que se recomienda sigue el orden de evaluación de S15 (sección 4.4):

1. **`FROM` y joins primero, con `SELECT *`.** Comprobar que el número de filas tiene sentido. Si un pedido tiene 3 líneas de detalle, el join `pedido ⋈ detalle` debe dar 3 filas para ese pedido, no 30. Muchas más filas de las esperadas es casi siempre una condición de join que falta (el producto cartesiano de S13).
2. **Agregar el `WHERE`** y volver a contar.
3. **Agregar el `GROUP BY` y los agregados**, con las columnas del grupo en el `SELECT`.
4. **Por último, `HAVING`, `ORDER BY` y `LIMIT`/`FETCH`.**

Un truco para el paso 1: `SELECT count(*) FROM …` con el mismo `FROM` y `WHERE` dice cuántas filas entran a la agregación. Y para cualquier subconsulta: correrla **sola** antes de meterla en la consulta grande (si es correlacionada, reemplazando la columna de afuera por un valor fijo).

### 3. Los reportes de la parte B

La sección 8 de la guía de S15 resolvió los cuatro reportes sobre el esquema `reportes_demo` (script [`S15-reportes-demo.sql`](S15-reportes-demo.sql)). En la parte B cada grupo los pasa a su esquema. Antes de la sesión, cada grupo revisa la sección 8.5 de S15 y anota qué le cambia: ¿el préstamo apunta al libro o a un ejemplar? ¿El nombre y el correo del lector están en `lector` o en `usuario`? ¿Hay una columna de estado o se calcula todo con fechas? ¿Dónde está la fecha esperada de devolución?

### 4. Datos de prueba que sí prueban algo

Un reporte que devuelve algo con los datos de la carga no está probado: los CSV semilla no traen préstamos, y con préstamos inventados al azar no se sabe qué resultado esperar. Lo que se pide es lo contrario: **primero decidir qué debe salir, después escribir los datos para que salga**. El script de S15 lo hace así, y sus casos son la lista mínima para la parte B:

| # | Caso | Dónde se nota | Qué debe pasar |
|---|---|---|---|
| 1 | Un libro que nadie ha prestado | Reporte 1 | Aparece con 0, o el grupo documenta que el reporte solo muestra libros prestados |
| 2 | Dos libros empatados en el último puesto del top | Reporte 1 | Salen los dos (o el grupo documenta otra regla de desempate) |
| 3 | Dos lectores empatados en el primer lugar de libros leídos | Reporte 2 | Salen los dos |
| 4 | Un lector con varios préstamos abiertos y ninguno devuelto | Reporte 2 | No sale (o sale con 0), aunque tenga más préstamos que los ganadores |
| 5 | Un préstamo devuelto después de la fecha esperada | Reportes 3 y 4 | No cuenta como mora: ya se devolvió |
| 6 | Un préstamo abierto que vence hoy | Reportes 3 y 4 | Según la regla del grupo (`<` o `<=`), documentada |
| 7 | Un lector con dos préstamos en mora | Reportes 3 y 4 | Aparece **una vez** en el 3 y **dos veces** en el 4 |
| 8 | Un lector sin ningún préstamo | Todos | No rompe nada ni aparece donde no debe |

Las fechas se escriben relativas a `CURRENT_DATE` (`CURRENT_DATE - 30`), igual que en `S15-reportes-demo.sql`: así los casos de mora siguen siendo mora el día de la sustentación. Si el esquema del grupo tiene reglas que impiden algún caso (por ejemplo, un `CHECK` que no deja registrar un préstamo en el pasado), el grupo lo anota y prueba lo que sí se puede.

**Pre-trabajo (20 min, antes de la sesión):**

1. Correr `S16-tienda.sql` y leer las tablas (`SELECT * FROM` cada una; son pequeñas).
2. Correr `S15-reportes-demo.sql` y comparar cada reporte con los casos de la tabla anterior.
3. Tener corriendo el esquema del grupo con los libros y lectores cargados (lo de S14) y las respuestas a las preguntas de la sección 3.

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor construye en vivo, por capas (sección 2), el ejercicio 5 de la parte A, mostrando el conteo de filas en cada paso. Termina con una pregunta: ¿qué pasa con el resultado si se olvida el filtro de cancelados? (Respuesta: los totales suben y **Accesorio** pasa al primer lugar, por el molino y la prensa de los pedidos cancelados.)
2. **(50 min) Parte A: ejercicios sobre `tienda`.** En parejas dentro del grupo; todo el grupo entrega un solo archivo `parte-a.sql` con las 11 consultas. Cada ejercicio trae el número de filas esperado para que la pareja se autocorrija: si no coincide, la consulta está mal (aunque "se vea bien"). El profesor y el monitor circulan por las salas.
3. **(10 min) Puesta en común.** Dos grupos comparten pantalla: uno con el ejercicio 9 (la trampa de `NOT IN`) y otro con el 11 (la división), explicando por qué su consulta es correcta.
4. **(40 min) Parte B: los cuatro reportes sobre el esquema propio.**
   - Escribir `datos-prueba.sql` con los préstamos (y lo que haga falta: ejemplares, devoluciones) que cubren los 8 casos de la sección 4, y anotar **antes de correr nada** qué debe devolver cada reporte.
   - Escribir `reportes.sql` con las cuatro consultas. Cada una lleva un comentario encima: qué devuelve, qué decisiones tomó el grupo (empates, `<` o `<=`, estado o fechas, libros sin préstamos) y el resultado esperado con los datos de prueba.
   - Correr y comparar. Si algún resultado no coincide con lo esperado, decidir si el error está en la consulta o en la expectativa, y anotarlo.
5. **(10 min) Cierre y checkpoint del Hito 2.** Cada grupo revisa contra la lista de la sección "Checkpoint" qué le falta del Hito 2. El profesor recuerda la fecha de entrega y que en M5 (S17 a S20) se analiza la normalización de este mismo esquema (Hito 3).

### Parte A: ejercicios

Todos sobre el esquema `tienda`. "Sin cancelados" quiere decir: sin los pedidos con `estado = 'cancelado'`.

| # | Enunciado | Practica | Filas esperadas |
|---|---|---|---|
| 1 | Para el pedido 1003: nombre del cliente, nombre de cada producto, cantidad y subtotal (`cantidad * precio_unitario`). | Join de 4 tablas | 2 |
| 2 | Cada cliente con el nombre del cliente que lo refirió; los que llegaron solos también deben aparecer. | Self-join externo | 8 |
| 3 | Productos que nunca se han vendido (en ningún pedido, ni siquiera cancelado). | Anti-join | 1 |
| 4 | Cada cliente con su número de pedidos (todos, incluidos los cancelados), mostrando 0 para quien no tiene ninguno. Ordenado de más a menos pedidos. | `LEFT JOIN` + `count` | 8 |
| 5 | Total vendido por categoría, sin cancelados, de mayor a menor. | `GROUP BY` | 3 |
| 6 | Meses de 2026 en que las ventas (sin cancelados) pasaron de $200 000, con su total. *Pista: `extract(month FROM fecha)` da el número del mes.* | `HAVING` | 2 |
| 7 | Productos cuyo precio es mayor que el precio promedio de **su** categoría. | Subconsulta correlacionada | 4 |
| 8 | Clientes de Cali que han comprado al menos un accesorio, sin cancelados. Cada cliente una sola vez. | `EXISTS` | 2 |
| 9 | Un compañero escribió esta consulta para "clientes que no han referido a nadie" y le devuelve 0 filas: `SELECT nombre FROM cliente WHERE id_cliente NOT IN (SELECT referido_por FROM cliente);` Explicar en un comentario por qué y escribir una versión correcta. | Trampa de `NOT IN` | 5 |
| 10 | El o los clientes que más han gastado (sin cancelados), con su total. | Máximo con empates | 2 |
| 11 | Clientes que han comprado **todos** los productos de la categoría Grano, sin cancelados. | División | 2 |

**Retos (opcionales, no suman a la rúbrica):**

- **R1.** Resolver el ejercicio 11 también con conteo (`GROUP BY` + `HAVING count(…) = (SELECT count(*) …)`). ¿Da lo mismo con `count(*)` que con `count(DISTINCT …)`? ¿Por qué? *(Pista: mirar todos los pedidos de Felipe.)*
- **R2.** ¿Qué devuelven las dos versiones del ejercicio 11 si se cambia `'Grano'` por una categoría sin productos? Explicar la diferencia con la sección 6.2 de S15.
- **R3.** Para cada cliente referido, ¿gastó más o menos que quien lo refirió? (Mostrar los dos nombres y los dos totales.)

### Parte B: los cuatro reportes sobre el esquema propio

Los mismos cuatro del documento del proyecto (sección 3.1), con las reglas por defecto de la sección 3.2 o las que el grupo haya documentado:

1. Los 20 libros más prestados.
2. El o los lectores que más libros han leído (préstamos devueltos).
3. Lectores morosos (con al menos un préstamo vencido y no devuelto), cada uno una vez.
4. Préstamos en mora, con el nombre del lector, su correo y su teléfono (la lista del botón "Enviar notificación").

Para la API de M7 conviene, aunque no se exige hoy, dejar cada reporte guardado como **vista**: `CREATE VIEW reporte_morosos AS SELECT …;` y después `SELECT * FROM reporte_morosos;`. Una vista es una consulta con nombre que se usa como si fuera una tabla (Silberschatz, sección 4.2); la API puede leer de ella sin repetir la consulta.

## Entregable

**Por grupo**, subido después de terminar la sesión (y en el repositorio del grupo, que es lo que se revisa en el Hito 2):

1. `parte-a.sql`: las 11 consultas de la parte A, cada una con un comentario con su número y, en la 9, la explicación.
2. `datos-prueba.sql` y `reportes.sql` (parte B), en `postgres/scripts/`.
3. Una tabla de verificación de la parte B, con una fila por caso de la sección 4: caso, resultado esperado, resultado obtenido y, si no coincidieron, qué se corrigió.
4. La salida de `psql` (texto o captura) de los cuatro reportes con los datos de prueba.

## Checkpoint del Hito 2

El Hito 2 (sección 8 del documento del proyecto) pide, en el repositorio del grupo:

| Pieza | Dónde quedó | Sesión |
|---|---|---|
| Esquema que corre limpio desde `postgres/init/` con la base vacía | `postgres/init/01_esquema.sql` | S14 |
| Carga de libros y lectores desde CSV, con el semilla y con un CSV propio | `postgres/scripts/carga-*.sql` y `postgres/scripts/datos/` | S14 |
| Validación de filas mal formadas y duplicados, con bitácora | Los mismos scripts de carga, y la tabla de criterios | S14 |
| Las consultas de los 4 reportes, documentadas | `postgres/scripts/reportes.sql` (y `datos-prueba.sql`) | S16 |

Si algo de S14 quedó pendiente, este es el momento de anotarlo. La rúbrica del Hito 2 está en la sección 9 del documento del proyecto; el último criterio ("las 4 consultas devuelven resultados correctos") se evalúa con los datos de prueba del grupo, así que la tabla de verificación es la evidencia.

## Rúbrica (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Parte A: consultas** | Menos de 6 ejercicios dan el número de filas esperado | Entre 6 y 9 | 10 u 11, incluidos el 10 y el 11 |
| **Parte A: diagnóstico del `NOT IN`** | No hay explicación, o es incorrecta | Corrige la consulta, pero la explicación no menciona el `NULL` | Explica que `referido_por` trae `NULL` y por qué eso vacía el `NOT IN`, y la corrige (con `NOT EXISTS` o filtrando el `NULL`) |
| **Parte B: datos de prueba** | No hay datos de préstamos, o son al azar sin resultado esperado | Cubren algunos de los 8 casos, o falta el resultado esperado | Cubren los 8 casos (o documentan por qué alguno no aplica), con fechas relativas a `CURRENT_DATE` y el resultado esperado escrito antes |
| **Parte B: los cuatro reportes** | Falta uno o más | Están los cuatro, pero alguno falla en un caso de prueba (empates, devueltos, mora repetida) | Los cuatro coinciden con lo esperado en todos los casos, y cada uno documenta sus decisiones |

Máximo 8 puntos por grupo. Los dos criterios de la parte B son un avance del último criterio del Hito 2 ("consultas base de los 4 reportes"): lo que se califica hoy no reemplaza esa entrega.
