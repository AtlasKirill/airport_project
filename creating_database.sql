CREATE TABLE IF NOT EXISTS tariff (
  tariff_id     SERIAL PRIMARY KEY,
  price         FLOAT NOT NULL,
  large_luggage BOOLEAN DEFAULT TRUE,
  food          BOOLEAN DEFAULT FALSE
);


CREATE TABLE IF NOT EXISTS planes (
  plane_id   SERIAL PRIMARY KEY,
  flight_id  INTEGER REFERENCES flights (flight_id),
  seats_num  SMALLINT DEFAULT 40,
  company    VARCHAR,
  plane_type VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS seats (
  seat_id                SERIAL PRIMARY KEY,
  plane_id               INTEGER REFERENCES planes (plane_id),
  serial_number_in_plane INTEGER
);

CREATE TABLE IF NOT EXISTS occupancy (
  seat_id INTEGER REFERENCES seats (seat_id) UNIQUE,
  user_id INTEGER REFERENCES users (user_id)
);


CREATE TABLE IF NOT EXISTS flights (
  flight_id   SERIAL PRIMARY KEY,
  departure   VARCHAR(20) NOT NULL,
  destination VARCHAR(20) NOT NULL,
  flight_date TIMESTAMP WITH TIME ZONE,
  UNIQUE (departure, destination, flight_date)
);

CREATE TABLE IF NOT EXISTS tickets (
  ticket_id SERIAL PRIMARY KEY,
  tariff_id INTEGER REFERENCES tariff (tariff_id),
  seat_id   INTEGER REFERENCES seats (seat_id) UNIQUE,
  plane_id  INTEGER REFERENCES planes (plane_id),
  flight_id INTEGER REFERENCES flights (flight_id),
  user_id   INTEGER REFERENCES users (user_id)
);
ALTER TABLE public.tickets
  ADD CONSTRAINT tickets_id_flight_fkey
FOREIGN KEY (flight_id) REFERENCES flights (flight_id) ON DELETE CASCADE;


CREATE TABLE IF NOT EXISTS users (
  user_id      SERIAL PRIMARY KEY,
  name         VARCHAR                NOT NULL,
  login        VARCHAR,
  password     VARCHAR,
  status       VARCHAR DEFAULT 'user' NOT NULL,
  surname      VARCHAR                NOT NULL,
  passport_num VARCHAR(20) UNIQUE,
  phone_number VARCHAR,
  UNIQUE (password, login)
);

CREATE INDEX idx_user_name
  ON users (upper(login));
CREATE INDEX idx_flight_depart
  ON flights (departure, destination);


-- Checking is flight exists
CREATE OR REPLACE FUNCTION isFlightExists(flight INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM flights
                WHERE flight_id = flight)
  THEN
    status = FALSE;
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;


-- Checking is tariff exists
CREATE OR REPLACE FUNCTION isTariffExists(cur_tariff INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM tariff
                WHERE tariff_id = cur_tariff)
  THEN
    status = FALSE;
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;


-- Checking is seat exists
CREATE OR REPLACE FUNCTION isSeatExists(cur_seat INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM seats
                WHERE seat_id = cur_seat)
  THEN
    status = FALSE;
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;

-- Checking is user exists
CREATE OR REPLACE FUNCTION isUserExist(usr_id INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM users
                WHERE user_id = usr_id)
  THEN
    status = FALSE;
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;

-- Checking is plane exists
CREATE OR REPLACE FUNCTION isPlaneExists(plane INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM planes
                WHERE planes.plane_id = plane)
  THEN
    status = FALSE;
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;


-- Checking is admin
CREATE OR REPLACE FUNCTION isAdmin(in_user_id INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  status = EXISTS(SELECT *
                  FROM users
                  WHERE users.status = 'admin' AND user_id = in_user_id);
  RETURN;
END;
$$
LANGUAGE plpgsql;

-- User registration
CREATE OR REPLACE FUNCTION registration(name    VARCHAR, login VARCHAR, password VARCHAR,
                                        surname VARCHAR, passport VARCHAR, phone VARCHAR DEFAULT '',
                                        status  VARCHAR DEFAULT 'user')
  RETURNS BOOLEAN AS $$
DECLARE user_id INTEGER;
BEGIN
  INSERT INTO users (name, login, password, status, surname, passport_num, phone_number)
  VALUES (name, login, password, status,
          surname, passport, phone)
  RETURNING users.user_id
    INTO user_id;
  IF user_id IS NOT NULL
  THEN RETURN TRUE;
  ELSE RETURN FALSE;
  END IF;
END
$$
LANGUAGE plpgsql;

SELECT *
FROM registration('vasya', 'asdmlld@.com', '21313', 'ivanov', 'en234', '+728499');


-- User Authorization
CREATE OR REPLACE FUNCTION authrorization(in_user_id INTEGER, OUT authorized BOOLEAN, OUT status VARCHAR) AS $$
DECLARE
BEGIN
  authorized = EXISTS(SELECT *
                      FROM users
                      WHERE user_id = in_user_id);
  status = (SELECT users.status
            FROM users
            WHERE user_id = in_user_id);
  RETURN;
END
$$
LANGUAGE plpgsql;

SELECT *
FROM authrorization(40);
SELECT *
FROM authrorization(30);


-- Adding new flight
CREATE OR REPLACE FUNCTION new_flight(in_user_id       INTEGER,
                                      depart           VARCHAR,
                                      dest             VARCHAR,
                                      date             TIMESTAMP WITH TIME ZONE,
  OUT                                 operation_status BOOLEAN,
  OUT                                 flight           INTEGER)
AS $$
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN RAISE NOTICE 'Exception:wrong permissions for this user';
  ELSE
    INSERT INTO flights (departure, destination, flight_date) VALUES (depart, dest, date)
    RETURNING flights.flight_id
      INTO flight;
  END IF;
  operation_status = TRUE;
  RETURN;
END
$$
LANGUAGE plpgsql;

SELECT *
FROM new_flight(3, 'Москва', 'Самара', '2018-05-09 02:45' :: TIMESTAMP WITH TIME ZONE);

SELECT *
FROM new_flight(30, 'Москва', 'Самара', '2018-05-09 17:00:00' :: TIMESTAMP WITH TIME ZONE);


--Deleting flights
CREATE OR REPLACE FUNCTION delete_flight(in_user_id            INTEGER, depart VARCHAR, dest VARCHAR,
                                         flight_date_departure TIMESTAMP WITH TIME ZONE,
  OUT                                    operation_status      BOOLEAN)AS $$
DECLARE
  current_flight_id INTEGER DEFAULT NULL;
  current_plane_id  INTEGER;
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception:wrong permissions for this user';
  END IF;

  SELECT flights.flight_id
  FROM flights
  WHERE date_trunc('minute', flight_date) = date_trunc('minute', flight_date_departure) AND
        departure = depart AND destination = dest
  INTO current_flight_id;

  IF current_flight_id IS NULL
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception: THERE ARE NO SUCH FLIGHT';
  END IF;

  BEGIN
    DELETE FROM flights
    WHERE flights.flight_id = current_flight_id;

    EXCEPTION WHEN foreign_key_violation
    THEN
      UPDATE planes
      SET flight_id = NULL
      WHERE planes.flight_id = current_flight_id
      RETURNING planes.plane_id
        INTO current_plane_id;

      DELETE FROM occupancy
      USING seats
      WHERE seats.plane_id = current_plane_id AND seats.seat_id = occupancy.seat_id;

      DELETE FROM flights
      WHERE flights.flight_id =
            current_flight_id; --Automatically deletes tickets if tickets.flught_id has constraint(delete on cascade)
  END;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;

-- Following query needs a constraint (delete on cascade) in flights foreign key in tickets table
SELECT *
FROM delete_flight(30, 'Москва', 'Владивосток', '2018-05-10 16:00:00' :: TIMESTAMP WITH TIME ZONE);


-- Changing flights
CREATE OR REPLACE FUNCTION change_flight(in_user_id       INTEGER,
                                         change_flight_id INTEGER,
                                         date             TIMESTAMP WITH TIME ZONE,
                                         depart           VARCHAR DEFAULT '',
                                         dest             VARCHAR DEFAULT '',
  OUT                                    operation_status BOOLEAN) AS $$
DECLARE
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception:wrong permissions for this user';
  END IF;
  IF isFlightExists(change_flight_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception: THERE ARE NO SUCH FLIGHT';
  END IF;
  CASE WHEN depart = '' AND dest = ''
    THEN
      UPDATE flights
      SET flight_date = date
      WHERE flight_id = change_flight_id;
    WHEN depart != '' AND dest = ''
    THEN
      UPDATE flights
      SET flight_date = date, departure = depart
      WHERE flight_id = change_flight_id;
    WHEN dest != '' AND dest != ''
    THEN
      UPDATE flights
      SET flight_date = date, departure = depart, destination = dest
      WHERE flight_id = change_flight_id;
  END CASE;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM change_flight(30, 20, '2018-05-10 16:45:00' :: TIMESTAMP WITH TIME ZONE, 'Лондон', 'Лисабон');


-- Replace plane's flight (assuming that admin will do this operation when the flight was completed)
CREATE OR REPLACE FUNCTION replace_plane_flight(in_user_id       INTEGER,
                                                change_plane_id  INTEGER,
                                                change_flight_id INTEGER,
  OUT                                           operation_status BOOLEAN) AS $$
DECLARE
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception:wrong permissions for this user';
  ELSEIF isFlightExists(change_flight_id) IS NOT TRUE
    THEN
      operation_status = FALSE;
      RAISE NOTICE 'Exception: THERE ARE NO SUCH FLIGHT';

  ELSEIF isPlaneExists(change_plane_id) IS NOT TRUE
    THEN
      operation_status = FALSE;
      RAISE NOTICE 'Exception: THERE ARE NO SUCH PLANE';
  END IF;

  UPDATE planes
  SET flight_id = change_flight_id
  WHERE plane_id = change_plane_id;

  DELETE FROM occupancy
  USING seats
  WHERE seats.plane_id = change_plane_id AND seats.seat_id = occupancy.seat_id;

  DELETE FROM tickets
  WHERE flight_id = change_flight_id;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM replace_plane_flight(20, 5, 1);


-- trigger for adding tickets and after into occupancy
CREATE TRIGGER t_add_occupancy
  AFTER INSERT
  ON tickets
  FOR EACH ROW EXECUTE PROCEDURE add_to_occupancy();

CREATE OR REPLACE FUNCTION add_to_occupancy()
  RETURNS TRIGGER AS $$
DECLARE
BEGIN
  IF tg_op = 'INSERT'
  THEN
    INSERT INTO occupancy (seat_id, user_id) VALUES (NEW.seat_id, NEW.user_id);
    RETURN NEW;
  END IF;
END;
$$
LANGUAGE plpgsql;


-- trigger for deleting tickets and after from occupancy
CREATE TRIGGER t_del_occupancy
  BEFORE DELETE
  ON tickets
  FOR EACH ROW EXECUTE PROCEDURE del_from_occupancy();

CREATE OR REPLACE FUNCTION del_from_occupancy()
  RETURNS TRIGGER AS $$
DECLARE
BEGIN
  IF tg_op = 'DELETE'
  THEN
    DELETE FROM occupancy
    WHERE occupancy.seat_id = OLD.seat_id;
    RETURN OLD;
  END IF;
END;
$$
LANGUAGE plpgsql;


DELETE FROM tickets
WHERE seat_id = 37;

INSERT INTO tickets (tariff_id, seat_id, plane_id, flight_id, user_id) VALUES (1, 37, 1, 3, 30);


-- Adding plane
CREATE OR REPLACE FUNCTION new_plane(in_user_id       INTEGER, corp VARCHAR,
                                     num_seat         INTEGER,
                                     type_of_plane    VARCHAR,
                                     flight           INTEGER DEFAULT NULL,
  OUT                                operation_status BOOLEAN,
  OUT                                new_plane_id     INTEGER) AS $$
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception:wrong permissions for this user';
  END IF;
  INSERT INTO planes (flight_id, seats_num, company, plane_type)
  VALUES (flight, num_seat, corp, type_of_plane)
  RETURNING plane_id
    INTO new_plane_id;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM new_plane(30, 'МАУ', 40, 'Airbus A320-211', 1);

CREATE OR REPLACE FUNCTION buy_ticket(usr_id           INTEGER,
                                      cur_flight_id    INTEGER,
                                      cur_plane_id     INTEGER,
                                      cur_seat_id      INTEGER,
                                      cur_tariff_id    INTEGER,
  OUT                                 operation_status BOOLEAN,
  OUT                                 new_ticket_id    INTEGER) AS $$
DECLARE
BEGIN
  IF isUserExist(usr_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: user does not exist';
  END IF;
  IF isFlightExists(cur_flight_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: flight does not exist';
  END IF;
  IF isSeatExists(cur_seat_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: seat does not exist';
  END IF;
  IF isTariffExists(cur_tariff_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: tariff does not exist';
  END IF;
  IF isPlaneExists(cur_plane_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: plane does not exist';
  END IF;

  IF NOT EXISTS(SELECT *
      FROM planes
      WHERE plane_id = cur_plane_id AND flight_id = cur_flight_id)
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: this plane does not belong to this flight';
  END IF;

  IF NOT EXISTS(SELECT *
      FROM seats
      WHERE plane_id = cur_plane_id AND seat_id = cur_seat_id)
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: this seat does not belong to the plane';
  END IF;
  IF EXISTS(SELECT *
      FROM occupancy
      WHERE seat_id = cur_seat_id)
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: this seat is already occupied';
  END IF;
  INSERT INTO tickets (tariff_id, seat_id, plane_id, flight_id, user_id)
  VALUES (cur_tariff_id, cur_seat_id, cur_plane_id, cur_flight_id, usr_id)
  RETURNING ticket_id
    INTO new_ticket_id;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;

SELECT *
FROM buy_ticket(30, 3, 1, 26, 3);



--   returns date of selected flight
CREATE OR REPLACE FUNCTION current_flaight_date(current_flight_id INTEGER,
  OUT                                           date              TIMESTAMP WITH TIME ZONE) AS $$
BEGIN
  SELECT flight_date
  FROM flights
  WHERE flight_id = current_flight_id
  INTO date;
  IF date IS NULL
  THEN RAISE EXCEPTION 'Exception: there are no such flight';
  END IF;
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM current_flaight_date(20);

--consistency of numeration of seats in the plane
CREATE TRIGGER t_seats_consistency
  AFTER INSERT
  ON seats
  FOR EACH STATEMENT EXECUTE PROCEDURE seat_consist();

CREATE OR REPLACE FUNCTION seat_consist()
  RETURNS TRIGGER AS $$
BEGIN
  IF tg_op = 'INSERT'
  THEN

  END IF;
END;
$$
LANGUAGE plpgsql;

-- view that needs for consistency trigger
CREATE VIEW ordered_by_plane AS
  SELECT *
  FROM seats
  GROUP BY plane_id
  ORDER BY seat_id ASC;

