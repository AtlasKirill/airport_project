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
  flight_date TIMESTAMP,
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

CREATE TABLE IF NOT EXISTS logsForBudget (
  payment   INTEGER,
  flight_id INTEGER,
  plane_id  INTEGER,
  user_id   INTEGER,
  date      TIMESTAMP,
  tariff_id INTEGER
);

CREATE INDEX idx_user_name
  ON users (upper(login));
CREATE INDEX idx_flight_depart
  ON flights (departure, destination);

-- query that modifies user info
UPDATE users
SET passport_num = 'er56', login = 'ff', password = 'aaaa'
WHERE user_id = 3;


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


-- Checking is ticket exists
CREATE OR REPLACE FUNCTION isTicketExist(tick_id INTEGER, OUT status BOOLEAN) AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM tickets
                WHERE ticket_id = tick_id)
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
SELECT *
FROM isAdmin(30);


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
                                      date             TIMESTAMP,
  OUT                                 operation_status BOOLEAN,
  OUT                                 flight           INTEGER)
AS $$
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
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
FROM new_flight(3, 'Москва', 'Самара', '2018-05-09 02:45' :: TIMESTAMP);

SELECT *
FROM new_flight(30, 'Москва', 'Самара', '2018-05-09 17:00:00' :: TIMESTAMP);


--Deleting flights
CREATE OR REPLACE FUNCTION delete_flight(in_user_id            INTEGER, depart VARCHAR, dest VARCHAR,
                                         flight_date_departure TIMESTAMP,
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
  WHERE flight_date = flight_date_departure AND
        departure = depart AND destination = dest
  INTO current_flight_id;

  IF current_flight_id IS NULL
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';
  END IF;


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

    operation_status = TRUE;
    RETURN;
END;
$$
LANGUAGE plpgsql;

-- Following query needs a constraint (delete on cascade) in flights foreign key in tickets table
SELECT *
FROM delete_flight(30, 'qqqq', 'qqqq', '2018-05-16 18:06:57' :: TIMESTAMP);

-- t_flight_descriptin needs in finction delete_flight_by_id
CREATE TYPE T_FLIGHT_DESCRIPTION AS (depart VARCHAR, dest VARCHAR, flightDate TIMESTAMP );
CREATE OR REPLACE FUNCTION delete_flight_by_id(in_user_id INTEGER, flightId INTEGER)
  RETURNS VOID
AS $$
DECLARE
  flight T_FLIGHT_DESCRIPTION;
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  --     RETURN;
  END IF;
  IF NOT EXISTS(SELECT *
                FROM flights
                WHERE flight_id = flightId)
  THEN
    RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';
  --     RETURN;
  END IF;
  SELECT
    departure,
    destination,
    flight_date
  INTO flight
  FROM flights
  WHERE flight_id = flightId;
  PERFORM delete_flight(in_user_id, flight.depart, flight.dest, flight.flightDate);
  RETURN;
END;
$$
LANGUAGE plpgsql;

SELECT TIMESTAMP 'epoch' + 946659600 * INTERVAL '1 second';
SELECT *
FROM delete_flight_by_id(30, 86);
SELECT *
FROM delete_flight_by_id(30, 93);


-- Changing flights
CREATE OR REPLACE FUNCTION change_flight(in_user_id       INTEGER,
                                         change_flight_id INTEGER,
                                         date             TIMESTAMP,
                                         depart           VARCHAR DEFAULT '',
                                         dest             VARCHAR DEFAULT '',
  OUT                                    operation_status BOOLEAN) AS $$
DECLARE
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;
  IF isFlightExists(change_flight_id) IS NOT TRUE
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
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM change_flight(30, 20, '2018-05-10 16:45:00' :: TIMESTAMP, 'Лондон', 'Токио');


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
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  ELSEIF isFlightExists(change_flight_id) IS NOT TRUE
    THEN
      operation_status = FALSE;
      RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';

  ELSEIF isPlaneExists(change_plane_id) IS NOT TRUE
    THEN
      operation_status = FALSE;
      RAISE EXCEPTION 'Exception: THERE ARE NO SUCH PLANE';
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
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;
  IF flight IS NOT NULL
  THEN
    IF NOT isflightexists(flight)
    THEN
      RAISE EXCEPTION 'Exception: THERE ARE NO SUCH FLIGHT';
    END IF;
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
FROM buy_ticket(3, 3, 1, 32, 3);


-- function that returns user's ticket
CREATE OR REPLACE FUNCTION return_ticket(usr_id           INTEGER, cur_ticket_id INTEGER,
  OUT                                    operation_status BOOLEAN) AS $$
BEGIN
  IF isUserExist(usr_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: user does not exist';
  END IF;
  IF isTicketExist(cur_ticket_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: ticket does not exist';
  END IF;
  IF NOT EXISTS(SELECT *
                FROM tickets
                WHERE user_id = usr_id)
  THEN
    operation_status = FALSE;
    RAISE EXCEPTION 'Exception: this user does not have this ticket';
  END IF;
  DELETE FROM tickets
  WHERE ticket_id = cur_ticket_id;
  operation_status = TRUE;
  RETURN;
END;
$$
LANGUAGE plpgsql;

SELECT *
FROM return_ticket(30, 24);

--   returns date of selected flight by separated integers (yy,MM,dd,hh,mm)
CREATE OR REPLACE FUNCTION current_flaight_date(current_flight_id INTEGER,
  OUT                                           year              INTEGER,
  OUT                                           month             INTEGER,
  OUT                                           day               INTEGER,
  OUT                                           hour              INTEGER,
  OUT                                           minute            INTEGER) AS $$
DECLARE
  date TIMESTAMP;
BEGIN
  SELECT flight_date
  FROM flights
  WHERE flight_id = current_flight_id
  INTO date;
  IF date IS NULL
  THEN RAISE EXCEPTION 'Exception: there are no such flight';
  END IF;
  year = date_part('year', date);
  month = date_part('month', date);
  day = date_part('day', date);
  hour = date_part('hour', date);
  minute = date_part('minute', date);
  RETURN;
END;
$$
LANGUAGE plpgsql;


SELECT *
FROM current_flaight_date(20);


-- returns time of departure by destination, departure and date of flight
CREATE OR REPLACE FUNCTION current_time_by_flightDate(dep VARCHAR, dest VARCHAR, year INTEGER, month INTEGER,
                                                      day INTEGER)
  RETURNS TABLE(flightId INTEGER, hour DOUBLE PRECISION, minute DOUBLE PRECISION) AS $$
DECLARE
BEGIN
  RETURN QUERY SELECT
                 flights.flight_id,
                 date_part('hour', flights.flight_date),
                 date_part('minute', flights.flight_date)
               FROM flights
               WHERE departure = dep AND destination = dest AND
                     date_part('year', flights.flight_date) = year AND date_part('month', flights.flight_date) = month
                     AND date_part('day', flights.flight_date) = day;

END;
$$
LANGUAGE plpgsql;

SELECT *
FROM current_time_by_flightDate('Москва', 'Ростов', 2018, 5, 9);


-- show list of vacant seats in plane
CREATE OR REPLACE FUNCTION list_of_free_seats(plane INTEGER)
  RETURNS TABLE(seat_id INTEGER, seat_num INTEGER) AS $$
BEGIN
  RETURN QUERY SELECT
                 seats.seat_id,
                 seats.serial_number_in_plane
               FROM seats
                 LEFT JOIN occupancy o ON seats.seat_id = o.seat_id
               WHERE o.seat_id IS NULL AND plane_id = plane;
END;
$$
LANGUAGE plpgsql;

SELECT *
FROM list_of_free_seats(1);

-- --consistency of numeration of seats in the plane
-- CREATE TRIGGER t_seats_consistency
--   AFTER INSERT
--   ON seats
--   FOR EACH STATEMENT EXECUTE PROCEDURE seat_consist();
--
-- CREATE OR REPLACE FUNCTION seat_consist()
--   RETURNS TRIGGER AS $$
-- BEGIN
--   IF tg_op = 'INSERT'
--   THEN
--
--   END IF;
-- END;
-- $$
-- LANGUAGE plpgsql;
--
-- -- view that needs for consistency trigger
-- CREATE VIEW ordered_by_plane AS
--   SELECT *
--   FROM seats
--   GROUP BY plane_id
--   ORDER BY seat_id ASC;
--
-- SELECT *
-- FROM now();


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


-- adding plane cause adding seats referred to this plane
CREATE TRIGGER t_add_plane
  AFTER INSERT
  ON planes
  FOR EACH ROW EXECUTE PROCEDURE add_to_seats();

CREATE OR REPLACE FUNCTION add_to_seats()
  RETURNS TRIGGER AS $$
DECLARE
  cnt      INTEGER DEFAULT 1;
  num_seat INTEGER DEFAULT 40;
BEGIN
  IF tg_op = 'INSERT'
  THEN
    num_seat = NEW.seats_num;
    FOR cnt IN 1..num_seat LOOP
      INSERT INTO seats (plane_id, serial_number_in_plane)
      VALUES (new.plane_id, cnt);
    END LOOP;
    RETURN new;
  END IF;
END;
$$
LANGUAGE plpgsql;


CREATE TRIGGER t_del_plane
  BEFORE DELETE
  ON planes
  FOR EACH ROW EXECUTE PROCEDURE del_seats();

CREATE OR REPLACE FUNCTION del_seats()
  RETURNS TRIGGER AS $$
DECLARE
BEGIN
  IF tg_op = 'DELETE'
  THEN
    DELETE FROM seats
    WHERE seats.plane_id = old.plane_id;

    DELETE FROM tickets
    WHERE tickets.plane_id = old.plane_id;
    RETURN old;
  END IF;
END;
$$
LANGUAGE plpgsql;


-- make particular user an admin
CREATE OR REPLACE FUNCTION setAdmin(in_user_id INTEGER, to_user_id INTEGER)
  RETURNS VOID AS $$
BEGIN
  IF NOT isAdmin(in_user_id)
  THEN
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;
  UPDATE users
  SET status = 'admin'
  WHERE user_id = to_user_id;
END;
$$
LANGUAGE plpgsql;

SELECT *
FROM setAdmin(20, 3);
SELECT *
FROM setAdmin(30, 3);


-- plane has one particular flight
CREATE OR REPLACE FUNCTION buyRangeOfTicket(flight INTEGER, userId INTEGER, tariff INTEGER, amount INTEGER)
  RETURNS SETOF INTEGER AS $$
DECLARE
  plane INTEGER;
  seat  INTEGER DEFAULT 0;
BEGIN
  IF NOT isflightexists(flight)
  THEN
    RAISE EXCEPTION 'EXCEPTION: THERE ARE NO SUCH FLIGHT';
  END IF;
  IF NOT isUserExist(userId)
  THEN
    RAISE EXCEPTION 'EXCEPTION: USER DOES NOT EXIST';
  END IF;
  IF NOT isTariffExists(tariff)
  THEN
    RAISE EXCEPTION 'EXCEPTION: TARIFF DOES NOT EXIST';
  END IF;

  SELECT plane_id
  FROM planes
  WHERE flight_id = flight
  INTO plane;

  IF amount > (SELECT count(*)
               FROM seats
                 INNER JOIN planes p USING (plane_id)
               WHERE p.plane_id = plane)
  THEN
    RAISE EXCEPTION 'EXCEPTION: THIS AMOUNT OF TICKETS IS NOT AVAILABLE';
  END IF;
  FOR seat IN (SELECT seat_id
               FROM list_of_free_seats(plane)
               LIMIT amount) LOOP
    INSERT INTO tickets (tariff_id, seat_id, plane_id, flight_id, user_id)
    VALUES (tariff, seat, plane, flight, userId);
  END LOOP;
END;
$$
LANGUAGE plpgsql;

SELECT *
FROM buyRangeOfTicket(30, 3, 1, 20);


CREATE TRIGGER t_add_to_logs
  AFTER INSERT
  ON tickets
  FOR EACH ROW EXECUTE PROCEDURE add_to_logs();

CREATE OR REPLACE FUNCTION add_to_logs()
  RETURNS TRIGGER AS $$
DECLARE
  curPayment INTEGER;
  curDate    TIMESTAMP;
BEGIN
  IF tg_op = 'INSERT'
  THEN
    SELECT price
    FROM tariff
    WHERE tariff.tariff_id = new.tariff_id
    INTO curPayment;
    SELECT flight_date
    FROM flights
    WHERE flights.flight_id = new.flight_id
    INTO curDate;
    INSERT INTO logsForBudget (payment, flight_id, plane_id, user_id, date, tariff_id)
    VALUES (curPayment, new.flight_id, new.plane_id, new.user_id, curDate, new.tariff_id);
    RETURN new;
  END IF;
END;
$$
LANGUAGE plpgsql;

-- queries:

-- Просмотр дат рейсов с выбранным направлением
SELECT concat(flight_date :: DATE, ' ', flight_date :: TIME)
FROM flights
WHERE departure = 'Москва' AND destination = 'Ростов';


-- SELECT
--   logsForBudget.date::date,
--   sum(payment) OVER (ORDER BY ),
--   FROM logsForBudget




