SET search_path TO reservas;

-- ============================================================================
-- A1. Restricciones CHECK y acciones referenciales ON DELETE
-- ============================================================================

ALTER TABLE reserva
    ADD CONSTRAINT reserva_orden      CHECK (fin > inicio),
    ADD CONSTRAINT reserva_duracion   CHECK (fin - inicio <= interval '3 hours'),
    ADD CONSTRAINT reserva_horario    CHECK (
        inicio::date = fin::date
        AND inicio::time >= time '07:00'
        AND fin::time    <= time '21:00'
    ),
    ADD CONSTRAINT reserva_asistentes CHECK (asistentes > 0);

-- Acciones referenciales sobre las llaves foráneas creadas en S22-reservas.sql
ALTER TABLE sala_recurso
    DROP CONSTRAINT sala_recurso_id_sala_fkey,
    ADD CONSTRAINT sala_recurso_id_sala_fkey
        FOREIGN KEY (id_sala) REFERENCES sala(id_sala) ON DELETE CASCADE;

ALTER TABLE reserva
    DROP CONSTRAINT reserva_id_sala_fkey,
    ADD CONSTRAINT reserva_id_sala_fkey
        FOREIGN KEY (id_sala) REFERENCES sala(id_sala) ON DELETE RESTRICT;

ALTER TABLE reserva
    DROP CONSTRAINT reserva_codigo_fkey,
    ADD CONSTRAINT reserva_codigo_fkey
        FOREIGN KEY (codigo) REFERENCES estudiante(codigo) ON DELETE RESTRICT;


-- ============================================================================
-- A2. Funciones en SQL (LANGUAGE sql STABLE)
-- ============================================================================

-- Regla 4: horas reservadas (sin canceladas) en la semana del día dado
CREATE OR REPLACE FUNCTION horas_semana(p_codigo varchar, p_dia date)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        ROUND(
            SUM(EXTRACT(EPOCH FROM (fin - inicio)) / 3600.0)::numeric,
            1
        ),
        0.0
    )
    FROM   reserva
    WHERE  codigo = p_codigo
      AND  estado <> 'cancelada'
      AND  date_trunc('week', inicio) = date_trunc('week', p_dia::timestamp);
$$;

-- Regla 3: verdadero si la sala no tiene reservas activas que se crucen con [p_inicio, p_fin)
CREATE OR REPLACE FUNCTION sala_libre(
    p_sala    integer,
    p_inicio  timestamp,
    p_fin     timestamp,
    p_excluir integer DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM   reserva
        WHERE  id_sala = p_sala
          AND  estado  = 'activa'
          AND  (p_excluir IS NULL OR id <> p_excluir)
          AND  inicio < p_fin
          AND  p_inicio < fin
    );
$$;


-- ============================================================================
-- A3. Procedimientos almacenados: reservar y cancelar
-- ============================================================================

CREATE OR REPLACE PROCEDURE reservar(
    p_codigo     varchar,
    p_sala       integer,
    p_inicio     timestamp,
    p_fin        timestamp,
    p_asistentes integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sancionado_hasta date;
    v_capacidad        integer;
    v_activa           boolean;
    v_horas_actuales   numeric;
    v_horas_nuevas     numeric;
    v_id_reserva       integer;
BEGIN
    -- 1. Verificar estudiante y Regla 5 (sanción)
    SELECT sancionado_hasta
    INTO   v_sancionado_hasta
    FROM   estudiante
    WHERE  codigo = p_codigo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El estudiante con código % no existe.', p_codigo;
    END IF;

    IF v_sancionado_hasta IS NOT NULL AND v_sancionado_hasta >= CURRENT_DATE THEN
        RAISE EXCEPTION 'El estudiante % está sancionado hasta % y no puede reservar.',
            p_codigo, v_sancionado_hasta;
    END IF;

    -- 2. Verificar sala y Regla 2 (mantenimiento y capacidad)
    SELECT capacidad, activa
    INTO   v_capacidad, v_activa
    FROM   sala
    WHERE  id_sala = p_sala;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala % no existe.', p_sala;
    END IF;

    IF NOT v_activa THEN
        RAISE EXCEPTION 'La sala % se encuentra en mantenimiento y no admite reservas.', p_sala;
    END IF;

    IF p_asistentes > v_capacidad THEN
        RAISE EXCEPTION 'La sala % tiene capacidad para % personas; no admite % asistentes.',
            p_sala, v_capacidad, p_asistentes;
    END IF;

    -- 3. Regla 3: disponibilidad de horario (sin cruces activos)
    IF NOT sala_libre(p_sala, p_inicio, p_fin) THEN
        RAISE EXCEPTION 'La sala % ya tiene una reserva activa en ese horario.', p_sala;
    END IF;

    -- 4. Regla 4: máximo 6 horas por semana
    v_horas_actuales := horas_semana(p_codigo, p_inicio::date);
    v_horas_nuevas   := EXTRACT(EPOCH FROM (p_fin - p_inicio)) / 3600.0;

    IF v_horas_actuales + v_horas_nuevas > 6.0 THEN
        RAISE EXCEPTION 'El estudiante % superaría el límite de 6 horas semanales (lleva % h y solicita % h).',
            p_codigo, v_horas_actuales, ROUND(v_horas_nuevas::numeric, 1);
    END IF;

    -- Inserción (los CHECK validan orden, duración <= 3h, horario 7-21 y asistentes > 0)
    INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes, estado)
    VALUES (p_sala, p_codigo, p_inicio, p_fin, p_asistentes, 'activa')
    RETURNING id INTO v_id_reserva;

    RAISE NOTICE 'Reserva #% creada exitosamente.', v_id_reserva;
END;
$$;

-- Regla 6: cancelar solo si está activa y no ha empezado
CREATE OR REPLACE PROCEDURE cancelar(p_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado varchar;
    v_inicio timestamp;
BEGIN
    SELECT estado, inicio
    INTO   v_estado, v_inicio
    FROM   reserva
    WHERE  id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La reserva % no existe.', p_id;
    END IF;

    IF v_estado <> 'activa' THEN
        RAISE EXCEPTION 'La reserva % no se puede cancelar porque su estado actual es "%".',
            p_id, v_estado;
    END IF;

    IF v_inicio <= now() THEN
        RAISE EXCEPTION 'La reserva % ya comenzó (%) y no puede cancelarse.',
            p_id, v_inicio;
    END IF;

    UPDATE reserva
    SET    estado = 'cancelada'
    WHERE  id = p_id;

    RAISE NOTICE 'Reserva #% cancelada.', p_id;
END;
$$;


-- ============================================================================
-- A4. Trigger BEFORE INSERT OR UPDATE de validación (Reglas 2 y 3)
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_reserva()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacidad integer;
    v_activa    boolean;
BEGIN
    -- Solo validar reservas activas
    IF NEW.estado <> 'activa' THEN
        RETURN NEW;
    END IF;

    -- Regla 2: existencia de sala, estado activo y capacidad suficiente
    SELECT capacidad, activa
    INTO   v_capacidad, v_activa
    FROM   sala
    WHERE  id_sala = NEW.id_sala;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se puede reservar: la sala % no existe.', NEW.id_sala;
    END IF;

    IF NOT v_activa THEN
        RAISE EXCEPTION 'No se puede reservar: la sala % está en mantenimiento.', NEW.id_sala;
    END IF;

    IF NEW.asistentes > v_capacidad THEN
        RAISE EXCEPTION 'No se puede reservar: la sala % admite máximo % personas (solicitadas: %).',
            NEW.id_sala, v_capacidad, NEW.asistentes;
    END IF;

    -- Regla 3: sin cruce horario con otras reservas activas (excluyendo NEW.id en UPDATE)
    IF NOT sala_libre(NEW.id_sala, NEW.inicio, NEW.fin, NEW.id) THEN
        RAISE EXCEPTION 'No se puede reservar: la sala % ya tiene una reserva activa en ese horario.',
            NEW.id_sala;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserva_validar ON reserva;
CREATE TRIGGER reserva_validar
    BEFORE INSERT OR UPDATE ON reserva
    FOR EACH ROW
    EXECUTE FUNCTION validar_reserva();


-- ============================================================================
-- A5. Trigger AFTER UPDATE OF estado para sancionar inasistencia (Regla 5)
-- ============================================================================

CREATE OR REPLACE FUNCTION sancionar_inasistencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE estudiante
    SET    sancionado_hasta = GREATEST(COALESCE(sancionado_hasta, CURRENT_DATE), CURRENT_DATE + 7)
    WHERE  codigo = NEW.codigo;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserva_sancionar ON reserva;
CREATE TRIGGER reserva_sancionar
    AFTER UPDATE OF estado ON reserva
    FOR EACH ROW
    WHEN (NEW.estado = 'no_asistio' AND OLD.estado <> 'no_asistio')
    EXECUTE FUNCTION sancionar_inasistencia();


-- ============================================================================
-- A6. Procedimiento basado en conjuntos: cerrar_vencidas()
-- ============================================================================

CREATE OR REPLACE PROCEDURE cerrar_vencidas()
LANGUAGE sql
AS $$
    UPDATE reserva
    SET    estado = 'cumplida'
    WHERE  estado = 'activa'
      AND  fin < now();
$$;


-- ============================================================================
-- Reto (opcional): Regla 3 como restricción EXCLUDE USING gist
-- ============================================================================
/*
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE reserva ADD CONSTRAINT reserva_sin_cruce
    EXCLUDE USING gist (id_sala WITH =, tsrange(inicio, fin) WITH &&)
    WHERE (estado = 'activa');

-- Prueba desactivando temporalmente reserva_validar:
ALTER TABLE reserva DISABLE TRIGGER reserva_validar;

-- Debe fallar por reserva_sin_cruce (se cruza con reserva 4 de Ana el martes 9:00-12:00):
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610006', dia(2) + time '10:00', dia(2) + time '11:00', 4);

-- Debe pasar (martes 14:00-16:00 está libre en Sala 3):
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610006', dia(2) + time '14:00', dia(2) + time '16:00', 4);
ROLLBACK;

ALTER TABLE reserva ENABLE TRIGGER reserva_validar;
*/