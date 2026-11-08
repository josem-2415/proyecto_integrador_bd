--REPORTES DED LA PARTE B 

--Los 20 libros más prestados.
WITH ranking_libros AS (
    SELECT pr.isbn , li.titulo , COUNT(pr.isbn) AS N_prestados, DENSE_RANK() OVER (ORDER BY COUNT(pr.isbn) DESC) AS posicion
    FROM prestamo pr
    INNER JOIN libro li ON li.isbn = pr.isbn
    GROUP BY pr.isbn , li.titulo
)

SELECT * 
FROM ranking_libros
ORDER BY posicion ASC
LIMIT 20;


-- El o los lectores que más libros han leído (préstamos devueltos)
WITH ranking_lector AS (
    SELECT u.id, u.documento, u.nombres, u.apellidos, COUNT(u.documento) AS n_libros_leidos, DENSE_RANK() OVER (ORDER BY COUNT(u.documento) DESC) AS posicion
    FROM usuario u
    INNER JOIN prestamo pr ON pr.id_lector = u.id
    WHERE u.id_rol = 1 AND pr.estado = 'devuelto'
    GROUP BY u.id, u.documento, u.nombres, u.apellidos
)

SELECT r.id, r.documento, r.nombres, r.apellidos, r.n_libros_leidos
FROM ranking_lector r
WHERE posicion = 1 ;

-- Lectores morosos (con al menos un préstamo vencido y no devuelto), cada uno una vez.
SELECT u.id, u.documento, u.nombres, u.apellidos
FROM usuario u
INNER JOIN prestamo pr ON pr.id_lector = u.id
WHERE u.id_rol = 1 AND pr.estado = 'en_mora'
GROUP BY u.id, u.documento, u.nombres, u.apellidos;


-- || Préstamos en mora, con el nombre del lector, su correo y su teléfono (la lista del botón "Enviar notificación"). || --
SELECT 
    STRING_AGG(pr.id::text, ', ') AS ids_prestamos,  -- la funcion string agg sirve para crear la lista de id de pretamos en mora q tiene el lector 
    u.nombres, 
    u.correo, 
    u.telefono
FROM prestamo pr
INNER JOIN usuario u ON u.id = pr.id_lector
WHERE pr.estado = 'en_mora'
GROUP BY u.nombres, u.correo, u.telefono;