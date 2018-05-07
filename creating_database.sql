CREATE TABLE IF NOT EXISTS tariff (
  tariff_id     SERIAL PRIMARY KEY,
  price         FLOAT NOT NULL,
  large_luggage BOOLEAN DEFAULT TRUE
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
  seat_id INTEGER REFERENCES seats (seat_id),
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

-- Checking is admin
CREATE OR REPLACE FUNCTION isAdmin(in_user_id INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  status = EXISTS(SELECT *
                  FROM users
                  WHERE users.status = 'admin' AND user_id = in_user_id);
END;$$
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
  THEN RAISE EXCEPTION 'Exception:wrong permissions for this user';
  ELSE
    INSERT INTO flights (departure, destination, flight_date) VALUES (depart, dest, date)
    RETURNING flights.flight_id
      INTO flight;
  END IF;
  operation_status = TRUE;
END
$$
LANGUAGE plpgsql;

SELECT *
FROM new_flight(3, 'Москва', 'Самара', '2018-05-09 02:00:00' :: TIMESTAMP WITH TIME ZONE);

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
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;

  SELECT flights.flight_id
  FROM flights
  WHERE date_trunc('minute', flight_date) = date_trunc('minute', flight_date_departure) AND
        departure = depart AND destination = dest
  INTO current_flight_id;

  IF current_flight_id IS NULL
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';
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
  THEN RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;
  IF NOT EXISTS(SELECT *
                FROM flights
                WHERE flight_id = change_flight_id)

  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';
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
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM change_flight(30, 20, '2018-05-10 16:45:00' :: TIMESTAMP WITH TIME ZONE, 'Лондон', 'Лисабон');


-- Replace plane's flight (assuming that admin will do this operation when the flight was completed)
CREATE OR REPLACE FUNCTION replace_plane_flight(in_user_id INTEGER, change_flight_id INTEGER, )


















