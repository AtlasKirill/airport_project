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
  flight_date TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS tickets (
  ticket_id SERIAL PRIMARY KEY,
  tariff_id INTEGER REFERENCES tariff (tariff_id),
  seat_id   INTEGER REFERENCES seats (seat_id) UNIQUE,
  plane_id  INTEGER REFERENCES planes (plane_id),
  flight_id INTEGER REFERENCES flights (flight_id),
  user_id   INTEGER REFERENCES users (user_id)
);


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
  IF (SELECT status
      FROM users
      WHERE user_id = in_user_id) != 'admin'
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
FROM new_flight(3, 'Москва', 'Владивосток', now() :: DATE + INTEGER '3'+interval'16 hour');

SELECT *
FROM new_flight(30, 'Москва', 'Владивосток', now() :: DATE + INTEGER '3'+interval'16 hour');



--




