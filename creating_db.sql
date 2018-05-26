--
-- PostgreSQL database dump
--

-- Dumped from database version 10.4 (Ubuntu 10.4-1.pgdg16.04+1)
-- Dumped by pg_dump version 10.4 (Ubuntu 10.4-1.pgdg16.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: t_flight_description; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.t_flight_description AS (
	depart character varying,
	dest character varying,
	flightdate timestamp without time zone
);


--
-- Name: add_to_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_to_logs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: add_to_occupancy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_to_occupancy() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
  IF tg_op = 'INSERT'
  THEN
    INSERT INTO occupancy (seat_id, user_id,flight_id) VALUES (NEW.seat_id, NEW.user_id,NEW.flight_id);
    RETURN NEW;
  END IF;
END;
$$;


--
-- Name: add_to_seats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_to_seats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: buy_ticket(integer, integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.buy_ticket(usr_id integer, cur_flight_id integer, cur_plane_id integer, cur_seat_id integer, cur_tariff_id integer, OUT operation_status boolean, OUT new_ticket_id integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
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
            WHERE seat_id = cur_seat_id AND flight_id = cur_flight_id)
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
$$;


--
-- Name: buyrangeofticket(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.buyrangeofticket(flight integer, userid integer, tariff integer, amount integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
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
               FROM list_of_free_seats(flight))
  THEN
    RAISE EXCEPTION 'EXCEPTION: THIS AMOUNT OF TICKETS IS NOT AVAILABLE';
  END IF;
  FOR seat IN (SELECT seat_id
               FROM list_of_free_seats(flight)
               LIMIT amount) LOOP
    INSERT INTO tickets (tariff_id, seat_id, plane_id, flight_id, user_id)
    VALUES (tariff, seat, plane, flight, userId);
  END LOOP;
END;
$$;


--
-- Name: change_flight(integer, integer, timestamp without time zone, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.change_flight(in_user_id integer, change_flight_id integer, date timestamp without time zone, depart character varying DEFAULT ''::character varying, dest character varying DEFAULT ''::character varying, OUT operation_status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: current_flaight_date(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_flaight_date(current_flight_id integer, OUT year integer, OUT month integer, OUT day integer, OUT hour integer, OUT minute integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  date TIMESTAMP ;
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
$$;


--
-- Name: current_time_by_flightdate(character varying, character varying, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_time_by_flightdate(dep character varying, dest character varying, year integer, month integer, day integer) RETURNS TABLE(flightid integer, hour double precision, minute double precision)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: del_from_occupancy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.del_from_occupancy() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
  IF tg_op = 'DELETE'
  THEN
    DELETE FROM occupancy
    WHERE occupancy.seat_id = OLD.seat_id AND occupancy.flight_id=OLD.flight_id;
    RETURN OLD;
  END IF;
END;
$$;


--
-- Name: del_seats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.del_seats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: delete_flight(integer, character varying, character varying, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_flight(in_user_id integer, depart character varying, dest character varying, flight_date_departure timestamp without time zone, OUT operation_status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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

    DELETE FROM flights
    WHERE flights.flight_id =
          current_flight_id; --Automatically deletes tickets AND occupancy if tickets.flight_id has constraint(delete on cascade)

    operation_status = TRUE;
    RETURN;
END;
$$;


--
-- Name: delete_flight_by_id(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_flight_by_id(in_user_id integer, flightid integer) RETURNS void
    LANGUAGE plpgsql
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
$$;


--
-- Name: income_in_direction(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.income_in_direction(depart character varying, dest character varying) RETURNS TABLE(date_time date, sum bigint, total bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY SELECT DISTINCT
                 logsForBudget.date :: DATE,
                 sum(payment)
                 OVER (
                   PARTITION BY date :: DATE ),
                 sum(payment)
                 OVER ()
               FROM logsForBudget
               WHERE flight_id IN (SELECT flights.flight_id
                                   FROM flights
                                   WHERE departure = depart AND destination = dest) AND
                     date_part('month', date) = date_part('month', now()) AND
                     date_part('year', date) = date_part('year', now())
               ORDER BY date :: DATE;
END;
$$;


--
-- Name: info_from_ticket(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.info_from_ticket(ticket integer) RETURNS TABLE(user_name text, passport character varying, direction text, date text, seat_num integer, plane_company character varying, food_and_luggage text)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY SELECT
                 u.name || ' ' || u.surname,
                 u.passport_num,
                 f.departure || '--->' || f.destination,
                 f.flight_date :: DATE || ' ' || f.flight_date :: TIME,
                 s.serial_number_in_plane,
                 p.company,
                 t2.food || ' and ' || t2.large_luggage
               FROM tickets t
                 LEFT JOIN users u ON t.user_id = u.user_id
                 LEFT JOIN flights f ON t.flight_id = f.flight_id
                 LEFT JOIN seats s ON t.seat_id = s.seat_id
                 LEFT JOIN planes p ON t.plane_id = p.plane_id
                 LEFT JOIN tariff t2 ON t.tariff_id = t2.tariff_id
               WHERE ticket_id = ticket;

END;
$$;


--
-- Name: isadmin(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isadmin(in_user_id integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  status = EXISTS(SELECT *
                  FROM users
                  WHERE users.status = 'admin' AND user_id = in_user_id);
  RETURN;
END;
$$;


--
-- Name: isflightexists(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isflightexists(flight integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: isplaneexists(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isplaneexists(plane integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: isseatexists(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isseatexists(cur_seat integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: istariffexists(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.istariffexists(cur_tariff integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: isticketexist(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isticketexist(tick_id integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: isuserexist(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isuserexist(usr_id integer, OUT status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS(SELECT *
                FROM users
                WHERE user_id = usr_id)
  THEN
    status = FALSE;
    RAISE EXCEPTION 'user does not exist';
  ELSE status = TRUE;
  END IF;
  RETURN;
END;
$$;


--
-- Name: list_of_free_seats(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_of_free_seats(flight integer) RETURNS TABLE(seat_id integer, seat_num integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY SELECT
                 seats.seat_id,
                 seats.serial_number_in_plane
               FROM seats
                 LEFT JOIN occupancy o USING (seat_id)
               WHERE o.seat_id IS NULL AND plane_id=(SELECT plane_id FROM planes WHERE planes.flight_id=flight);
END;
$$;


--
-- Name: new_flight(integer, character varying, character varying, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_flight(in_user_id integer, depart character varying, dest character varying, date timestamp without time zone, OUT operation_status boolean, OUT flight integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF isAdmin(in_user_id) IS NOT TRUE
  THEN
    operation_status = FALSE;
    RAISE NOTICE 'Exception:wrong permissions for this user';
  ELSE
    INSERT INTO flights (departure, destination, flight_date) VALUES (depart, dest, date)
    RETURNING flights.flight_id
      INTO flight;
  END IF;
  operation_status = TRUE;
  RETURN;
END
$$;


--
-- Name: new_plane(integer, character varying, integer, character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_plane(in_user_id integer, corp character varying, num_seat integer, type_of_plane character varying, flight integer, OUT operation_status boolean, OUT new_plane_id integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: registration(character varying, character varying, character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registration(name character varying, login character varying, password character varying, surname character varying, passport character varying, phone character varying DEFAULT ''::character varying, status character varying DEFAULT 'user'::character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: replace_plane_flight(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.replace_plane_flight(in_user_id integer, change_plane_id integer, change_flight_id integer, OUT operation_status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  prev_flight_id INTEGER;
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
  SELECT flight_id FROM planes WHERE plane_id=change_plane_id INTO prev_flight_id;
  UPDATE planes
  SET flight_id = change_flight_id
  WHERE plane_id = change_plane_id;

--   DELETE FROM occupancy
--   USING seats
--   WHERE seats.plane_id = change_plane_id AND seats.seat_id = occupancy.seat_id;

  DELETE FROM tickets
  WHERE flight_id = prev_flight_id;
  operation_status = TRUE;
  RETURN;
END;
$$;


--
-- Name: return_ticket(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.return_ticket(usr_id integer, cur_ticket_id integer, OUT operation_status boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: setadmin(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.setadmin(in_user_id integer, to_user_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN 
  IF NOT isAdmin(in_user_id) THEN 
    RAISE EXCEPTION 'Exception:wrong permissions for this user';
  END IF;
  UPDATE users SET status='admin' WHERE user_id=to_user_id;
END;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: flights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flights (
    flight_id integer NOT NULL,
    departure character varying(20) NOT NULL,
    destination character varying(20) NOT NULL,
    flight_date timestamp without time zone
);


--
-- Name: flights_flight_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flights_flight_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flights_flight_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flights_flight_id_seq OWNED BY public.flights.flight_id;


--
-- Name: logsforbudget; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logsforbudget (
    payment integer,
    flight_id integer,
    plane_id integer,
    user_id integer,
    date timestamp without time zone,
    tariff_id integer,
    log_id integer NOT NULL
);


--
-- Name: income_in_direction; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.income_in_direction AS
 SELECT DISTINCT (logsforbudget.date)::date AS date,
    sum(logsforbudget.payment) OVER (PARTITION BY ((logsforbudget.date)::date)) AS income_for_this_day,
    sum(logsforbudget.payment) OVER () AS total
   FROM public.logsforbudget
  WHERE ((logsforbudget.flight_id IN ( SELECT flights.flight_id
           FROM public.flights
          WHERE (((flights.departure)::text = 'Москва'::text) AND ((flights.destination)::text = 'Ростов'::text)))) AND (date_part('month'::text, logsforbudget.date) = date_part('month'::text, now())) AND (date_part('year'::text, logsforbudget.date) = date_part('year'::text, now())))
  ORDER BY ((logsforbudget.date)::date);


--
-- Name: logsforbudget_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.logsforbudget_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: logsforbudget_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.logsforbudget_log_id_seq OWNED BY public.logsforbudget.log_id;


--
-- Name: occupancy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.occupancy (
    seat_id integer,
    user_id integer,
    flight_id integer
);


--
-- Name: planes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planes (
    plane_id integer NOT NULL,
    seats_num smallint DEFAULT 40,
    company character varying,
    plane_type character varying(20),
    flight_id integer
);


--
-- Name: planes_plane_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planes_plane_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planes_plane_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planes_plane_id_seq OWNED BY public.planes.plane_id;


--
-- Name: seats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seats (
    seat_id integer NOT NULL,
    plane_id integer NOT NULL,
    serial_number_in_plane integer
);


--
-- Name: seats_seat_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seats_seat_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seats_seat_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seats_seat_id_seq OWNED BY public.seats.seat_id;


--
-- Name: tariff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tariff (
    tariff_id integer NOT NULL,
    price double precision NOT NULL,
    large_luggage boolean DEFAULT true,
    food boolean DEFAULT false
);


--
-- Name: tariff_tariff_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tariff_tariff_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tariff_tariff_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tariff_tariff_id_seq OWNED BY public.tariff.tariff_id;


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    ticket_id integer NOT NULL,
    tariff_id integer,
    seat_id integer,
    plane_id integer,
    flight_id integer,
    user_id integer
);


--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tickets_ticket_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tickets_ticket_id_seq OWNED BY public.tickets.ticket_id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    name character varying NOT NULL,
    login character varying,
    surname character varying NOT NULL,
    passport_num character varying(20),
    phone_number character varying,
    status character varying DEFAULT 'user'::character varying NOT NULL,
    password character varying
);


--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: flights flight_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flights ALTER COLUMN flight_id SET DEFAULT nextval('public.flights_flight_id_seq'::regclass);


--
-- Name: logsforbudget log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logsforbudget ALTER COLUMN log_id SET DEFAULT nextval('public.logsforbudget_log_id_seq'::regclass);


--
-- Name: planes plane_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes ALTER COLUMN plane_id SET DEFAULT nextval('public.planes_plane_id_seq'::regclass);


--
-- Name: seats seat_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seats ALTER COLUMN seat_id SET DEFAULT nextval('public.seats_seat_id_seq'::regclass);


--
-- Name: tariff tariff_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tariff ALTER COLUMN tariff_id SET DEFAULT nextval('public.tariff_tariff_id_seq'::regclass);


--
-- Name: tickets ticket_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets ALTER COLUMN ticket_id SET DEFAULT nextval('public.tickets_ticket_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Data for Name: flights; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.flights (flight_id, departure, destination, flight_date) FROM stdin;
1	Москва	Ростов	2018-05-09 06:45:00
30	Монако	Сызрань	2018-05-09 02:39:00
118	Москва	Ростов	2018-05-20 12:55:00
110	Брюссель	Амстердам	2039-12-31 21:00:00
121	Москва	Симферополь	2018-05-20 21:15:00
122	Москва	Симферополь	2018-05-19 10:15:00
123	Симферополь	Краснодар	2018-05-21 19:15:00
117	Москва	Санкт-Петербург	2018-05-09 13:00:00
\.


--
-- Data for Name: logsforbudget; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.logsforbudget (payment, flight_id, plane_id, user_id, date, tariff_id, log_id) FROM stdin;
1200	110	1	12	2018-05-10 16:45:00	6	568
1200	124	15	5	2018-05-11 16:45:00	6	569
1200	116	19	5	2018-05-12 16:45:00	3	570
1200	118	1	98	2018-05-13 16:45:00	3	571
1200	30	17	5	2018-05-14 16:45:00	6	572
1200	111	18	5	2018-05-15 16:45:00	3	573
1200	118	19	5	2018-05-16 16:45:00	3	574
1200	117	20	5	2018-05-17 16:45:00	5	575
1200	123	17	5	2018-05-18 16:45:00	5	576
1200	121	15	5	2018-05-19 16:45:00	5	577
1200	123	19	12	2018-05-20 16:45:00	3	578
1200	122	1	12	2018-05-21 16:45:00	5	579
1200	118	1	12	2018-05-22 16:45:00	6	580
1200	30	14	56	2018-05-23 16:45:00	6	581
1200	116	17	98	2018-05-24 16:45:00	6	582
1200	116	16	98	2018-05-25 16:45:00	3	583
1200	122	16	5	2018-05-26 16:45:00	3	584
1200	118	19	12	2018-05-27 16:45:00	3	585
1200	117	20	12	2018-05-28 16:45:00	1	586
1200	123	20	56	2018-05-29 16:45:00	3	587
1200	122	17	5	2018-05-30 16:45:00	5	588
1200	30	1	12	2018-05-31 16:45:00	3	589
1200	121	15	5	2018-06-01 16:45:00	1	590
1200	118	20	7	2018-06-02 16:45:00	3	591
1200	30	13	98	2018-06-03 16:45:00	6	592
1200	30	1	12	2018-06-04 16:45:00	3	593
1200	123	20	5	2018-06-05 16:45:00	6	594
1200	110	14	7	2018-06-06 16:45:00	3	595
1200	30	13	7	2018-06-07 16:45:00	3	596
1200	110	14	98	2018-06-08 16:45:00	3	597
1200	122	21	7	2018-06-09 16:45:00	3	598
1200	121	17	5	2018-06-10 16:45:00	6	599
1200	123	16	7	2018-06-11 16:45:00	5	600
1200	117	15	12	2018-06-12 16:45:00	3	601
1200	124	1	5	2018-06-13 16:45:00	6	602
1200	121	13	12	2018-06-14 16:45:00	5	603
1200	122	15	5	2018-06-15 16:45:00	3	604
1200	122	20	5	2018-06-16 16:45:00	6	605
1200	121	20	12	2018-06-17 16:45:00	3	606
1200	116	17	5	2018-06-18 16:45:00	1	607
1200	121	13	5	2018-06-19 16:45:00	1	608
1200	110	17	12	2018-06-20 16:45:00	6	609
1200	110	19	5	2018-06-21 16:45:00	3	610
1200	30	6	7	2018-06-22 16:45:00	5	611
1200	111	16	7	2018-06-23 16:45:00	1	612
1200	111	21	5	2018-06-24 16:45:00	6	613
1200	121	14	5	2018-06-25 16:45:00	5	614
1200	1	16	5	2018-06-26 16:45:00	6	615
1200	110	15	12	2018-06-27 16:45:00	3	616
1200	121	13	98	2018-06-28 16:45:00	3	617
1200	1	20	98	2018-06-29 16:45:00	1	618
1200	123	21	2	2018-06-30 16:45:00	1	619
1200	116	16	2	2018-07-01 16:45:00	3	620
1200	111	19	7	2018-07-02 16:45:00	5	621
1200	111	13	12	2018-07-03 16:45:00	3	622
1200	121	21	2	2018-07-04 16:45:00	3	623
1200	30	21	5	2018-07-05 16:45:00	5	624
1200	116	16	7	2018-07-06 16:45:00	3	625
1200	111	21	12	2018-07-07 16:45:00	1	626
1200	123	17	2	2018-07-08 16:45:00	1	627
1200	122	1	5	2018-07-09 16:45:00	5	628
1200	121	20	98	2018-07-10 16:45:00	5	629
1200	111	14	7	2018-07-11 16:45:00	5	630
1200	118	15	7	2018-07-12 16:45:00	6	631
1200	30	21	5	2018-07-13 16:45:00	3	632
1200	111	20	98	2018-07-14 16:45:00	3	633
1200	121	15	7	2018-07-15 16:45:00	6	634
1200	121	13	98	2018-07-16 16:45:00	3	635
1200	118	16	7	2018-07-17 16:45:00	3	636
1200	30	1	5	2018-07-18 16:45:00	3	637
1200	121	13	7	2018-07-19 16:45:00	3	638
1200	110	14	56	2018-07-20 16:45:00	6	639
1200	117	17	5	2018-07-21 16:45:00	6	640
1200	116	21	56	2018-07-22 16:45:00	5	641
1200	30	16	5	2018-07-23 16:45:00	6	642
1200	121	16	7	2018-07-24 16:45:00	3	643
1200	110	14	12	2018-07-25 16:45:00	6	644
1200	121	14	2	2018-07-26 16:45:00	3	645
1200	124	16	98	2018-07-27 16:45:00	6	646
1200	123	19	12	2018-07-28 16:45:00	3	647
1200	111	14	56	2018-07-29 16:45:00	3	648
1200	118	21	12	2018-07-30 16:45:00	6	649
1200	111	18	12	2018-07-31 16:45:00	5	650
1200	116	19	5	2018-08-01 16:45:00	5	651
1200	116	17	5	2018-08-02 16:45:00	1	652
1200	30	14	12	2018-08-03 16:45:00	1	653
1200	123	15	5	2018-08-04 16:45:00	5	654
1200	123	6	7	2018-08-05 16:45:00	1	655
1200	110	15	5	2018-08-06 16:45:00	1	656
1200	30	18	98	2018-08-07 16:45:00	3	657
1200	124	16	5	2018-08-08 16:45:00	3	658
1200	124	16	5	2018-08-09 16:45:00	3	659
1200	122	19	7	2018-08-10 16:45:00	6	660
1200	116	20	12	2018-08-11 16:45:00	3	661
1200	1	17	5	2018-08-12 16:45:00	5	662
1200	118	13	2	2018-08-13 16:45:00	1	663
1200	118	14	7	2018-08-14 16:45:00	6	664
1200	110	18	12	2018-08-15 16:45:00	6	665
1200	116	1	12	2018-08-16 16:45:00	3	666
1200	116	6	5	2018-08-17 16:45:00	1	667
1200	122	20	12	2018-08-18 16:45:00	1	668
1200	110	20	12	2018-08-19 16:45:00	6	669
1200	116	17	5	2018-08-20 16:45:00	6	670
1200	122	14	12	2018-08-21 16:45:00	3	671
1200	116	1	56	2018-08-22 16:45:00	5	672
1200	30	20	5	2018-08-23 16:45:00	3	673
1200	123	13	5	2018-08-24 16:45:00	3	674
1200	117	1	7	2018-08-25 16:45:00	3	675
1200	123	16	7	2018-08-26 16:45:00	6	676
1200	30	14	5	2018-08-27 16:45:00	3	677
1200	30	19	5	2018-08-28 16:45:00	5	678
1200	117	1	7	2018-08-29 16:45:00	6	679
1200	111	16	5	2018-08-30 16:45:00	3	680
1200	30	6	98	2018-08-31 16:45:00	1	681
1200	117	13	7	2018-09-01 16:45:00	6	682
1200	118	14	56	2018-09-02 16:45:00	3	683
1200	123	15	56	2018-09-03 16:45:00	5	684
1200	122	1	7	2018-09-04 16:45:00	5	685
1200	123	17	12	2018-09-05 16:45:00	3	686
1200	118	15	12	2018-09-06 16:45:00	6	687
1200	118	13	5	2018-09-07 16:45:00	6	688
1200	117	20	98	2018-09-08 16:45:00	6	689
1200	111	18	5	2018-09-09 16:45:00	6	690
1200	110	14	5	2018-09-10 16:45:00	6	691
1200	122	1	5	2018-09-11 16:45:00	6	692
1200	111	20	5	2018-09-12 16:45:00	1	693
1200	116	17	7	2018-09-13 16:45:00	5	694
1200	121	15	5	2018-09-14 16:45:00	3	695
1200	118	19	12	2018-09-15 16:45:00	5	696
1200	118	17	5	2018-09-16 16:45:00	6	697
1200	118	15	12	2018-09-17 16:45:00	1	698
1200	122	14	5	2018-09-18 16:45:00	6	699
1200	121	1	5	2018-09-19 16:45:00	5	700
1200	124	20	2	2018-09-20 16:45:00	3	701
1200	116	13	5	2018-09-21 16:45:00	5	702
1200	110	19	5	2018-09-22 16:45:00	1	703
1200	117	18	56	2018-09-23 16:45:00	5	704
1200	118	14	98	2018-09-24 16:45:00	5	705
1200	122	15	2	2018-09-25 16:45:00	6	706
1200	122	19	5	2018-09-26 16:45:00	3	707
1200	122	16	12	2018-09-27 16:45:00	6	708
1200	30	17	56	2018-09-28 16:45:00	3	709
1200	123	1	7	2018-09-29 16:45:00	3	710
1200	122	17	12	2018-09-30 16:45:00	3	711
1200	118	17	7	2018-10-01 16:45:00	5	712
1200	30	18	12	2018-10-02 16:45:00	5	713
1200	111	21	12	2018-10-03 16:45:00	5	714
1200	110	14	12	2018-10-04 16:45:00	3	715
1200	124	20	5	2018-10-05 16:45:00	1	716
1200	116	1	12	2018-10-06 16:45:00	3	717
1200	111	20	5	2018-10-07 16:45:00	1	718
1200	116	1	7	2018-10-08 16:45:00	6	719
1200	110	17	98	2018-10-09 16:45:00	6	720
1200	118	14	5	2018-10-10 16:45:00	6	721
1200	118	18	5	2018-10-11 16:45:00	1	722
1200	110	18	12	2018-10-12 16:45:00	6	723
1200	122	14	98	2018-10-13 16:45:00	1	724
1200	121	15	7	2018-10-14 16:45:00	5	725
1200	124	21	12	2018-10-15 16:45:00	3	726
1200	124	1	2	2018-10-16 16:45:00	6	727
1200	110	19	5	2018-10-17 16:45:00	1	728
1200	116	14	98	2018-10-18 16:45:00	5	729
1200	110	16	56	2018-10-19 16:45:00	3	730
1200	116	17	12	2018-10-20 16:45:00	1	731
1200	30	14	7	2018-10-21 16:45:00	6	732
1200	121	17	5	2018-10-22 16:45:00	6	733
1200	117	13	56	2018-10-23 16:45:00	3	734
1200	110	18	12	2018-10-24 16:45:00	3	735
1200	121	6	7	2018-10-25 16:45:00	5	736
1200	121	1	12	2018-10-26 16:45:00	3	737
1200	118	20	5	2018-10-27 16:45:00	6	738
1200	111	13	56	2018-10-28 16:45:00	3	739
1200	124	15	2	2018-10-29 16:45:00	6	740
1200	121	14	12	2018-10-30 16:45:00	1	741
1200	1	16	5	2018-10-31 16:45:00	6	742
1200	116	13	12	2018-11-01 16:45:00	5	743
1200	117	1	12	2018-11-02 16:45:00	1	744
1200	116	19	12	2018-11-03 16:45:00	6	745
1200	117	21	12	2018-11-04 16:45:00	6	746
1200	116	13	56	2018-11-05 16:45:00	3	747
1200	110	18	2	2018-11-06 16:45:00	3	748
1200	110	13	5	2018-11-07 16:45:00	6	749
1200	121	6	5	2018-11-08 16:45:00	1	750
1200	118	18	56	2018-11-09 16:45:00	5	751
1200	30	21	56	2018-11-10 16:45:00	3	752
1200	111	17	3	2018-12-31 10:00:00	1	1210
2500	111	17	3	2018-05-31 10:00:00	3	1213
1400	111	17	3	2018-05-31 10:00:00	5	1214
1400	111	17	3	2018-05-31 10:00:00	5	1211
1200	110	16	5	2018-11-11 16:45:00	5	753
1200	116	14	98	2018-11-12 16:45:00	6	754
1200	1	14	12	2018-11-13 16:45:00	6	755
1200	110	21	2	2018-11-14 16:45:00	1	756
1200	116	17	98	2018-11-15 16:45:00	1	757
1200	110	21	5	2018-11-16 16:45:00	1	758
1200	123	1	12	2018-11-17 16:45:00	5	759
1200	123	21	12	2018-11-18 16:45:00	3	760
1200	111	13	12	2018-11-19 16:45:00	6	761
1200	1	1	5	2018-11-20 16:45:00	1	762
1200	122	6	98	2018-11-21 16:45:00	3	763
1200	124	19	12	2018-11-22 16:45:00	3	764
1200	111	15	12	2018-11-23 16:45:00	6	765
1200	30	13	12	2018-11-24 16:45:00	5	766
1200	118	19	12	2018-11-25 16:45:00	3	767
1200	110	16	12	2018-11-26 16:45:00	5	768
1200	121	13	12	2018-11-27 16:45:00	6	769
1200	118	17	12	2018-11-28 16:45:00	3	770
1200	118	17	5	2018-11-29 16:45:00	6	771
1200	111	1	12	2018-11-30 16:45:00	3	772
1200	116	15	5	2018-12-01 16:45:00	3	773
1200	110	6	7	2018-12-02 16:45:00	1	774
1200	122	15	5	2018-12-03 16:45:00	3	775
1200	118	17	7	2018-12-04 16:45:00	3	776
1200	123	14	56	2018-12-05 16:45:00	3	777
1200	30	20	98	2018-12-06 16:45:00	6	778
1200	116	16	5	2018-12-07 16:45:00	3	779
1200	117	18	12	2018-12-08 16:45:00	6	780
1200	30	1	2	2018-12-09 16:45:00	6	781
1200	30	16	12	2018-05-10 16:45:00	6	782
1200	118	13	7	2018-05-11 16:45:00	5	783
1200	123	17	5	2018-05-12 16:45:00	6	784
1200	30	1	5	2018-05-13 16:45:00	3	785
1200	123	20	12	2018-05-14 16:45:00	3	786
1200	30	1	98	2018-05-15 16:45:00	6	787
1200	1	17	5	2018-05-16 16:45:00	1	788
1200	110	15	12	2018-05-17 16:45:00	6	789
1200	118	19	12	2018-05-18 16:45:00	5	790
1200	30	19	12	2018-05-19 16:45:00	5	791
1200	111	1	98	2018-05-20 16:45:00	3	792
1200	111	20	5	2018-05-21 16:45:00	1	793
1200	110	13	7	2018-05-22 16:45:00	6	794
1200	118	6	7	2018-05-23 16:45:00	6	795
1200	118	13	5	2018-05-24 16:45:00	1	796
1200	110	17	12	2018-05-25 16:45:00	1	797
1200	111	16	2	2018-05-26 16:45:00	3	798
1200	124	18	7	2018-05-27 16:45:00	1	799
1200	30	18	12	2018-05-28 16:45:00	3	800
1200	122	6	12	2018-05-29 16:45:00	3	801
1200	118	20	5	2018-05-30 16:45:00	5	802
1200	122	16	12	2018-05-31 16:45:00	3	803
1200	121	1	12	2018-06-01 16:45:00	3	804
1200	110	15	12	2018-06-02 16:45:00	6	805
1200	118	17	5	2018-06-03 16:45:00	6	806
1200	118	17	98	2018-06-04 16:45:00	6	807
1200	118	1	12	2018-06-05 16:45:00	3	808
1200	30	16	5	2018-06-06 16:45:00	6	809
1200	1	19	5	2018-06-07 16:45:00	6	810
1200	1	18	5	2018-06-08 16:45:00	6	811
1200	30	17	2	2018-06-09 16:45:00	6	812
1200	122	17	12	2018-06-10 16:45:00	3	813
1200	124	14	12	2018-06-11 16:45:00	3	814
1200	30	17	56	2018-06-12 16:45:00	6	815
1200	110	20	12	2018-06-13 16:45:00	6	816
1200	30	13	7	2018-06-14 16:45:00	1	817
1200	111	21	56	2018-06-15 16:45:00	3	818
1200	123	6	56	2018-06-16 16:45:00	5	819
1200	110	6	98	2018-06-17 16:45:00	3	820
1200	118	1	5	2018-06-18 16:45:00	3	821
1200	122	13	12	2018-06-19 16:45:00	5	822
1200	123	21	12	2018-06-20 16:45:00	6	823
1200	122	15	7	2018-06-21 16:45:00	5	824
1200	121	14	2	2018-06-22 16:45:00	6	825
1200	118	21	2	2018-06-23 16:45:00	3	826
1200	124	18	12	2018-06-24 16:45:00	6	827
1200	124	6	12	2018-06-25 16:45:00	3	828
1200	111	17	56	2018-06-26 16:45:00	5	829
1200	124	21	12	2018-06-27 16:45:00	5	830
1200	122	16	12	2018-06-28 16:45:00	6	831
1200	118	19	12	2018-06-29 16:45:00	3	832
1200	116	13	56	2018-06-30 16:45:00	6	833
1200	117	6	7	2018-07-01 16:45:00	3	834
1200	124	14	12	2018-07-02 16:45:00	5	835
1200	110	20	12	2018-07-03 16:45:00	5	836
1200	116	13	12	2018-07-04 16:45:00	3	837
1200	116	19	5	2018-07-05 16:45:00	1	838
1200	124	14	98	2018-07-06 16:45:00	3	839
1200	116	1	98	2018-07-07 16:45:00	6	840
1200	110	19	12	2018-07-08 16:45:00	5	841
1200	121	14	7	2018-07-09 16:45:00	6	842
1200	111	15	5	2018-07-10 16:45:00	6	843
1200	124	1	98	2018-07-11 16:45:00	3	844
1200	118	17	5	2018-07-12 16:45:00	6	845
1200	111	20	56	2018-07-13 16:45:00	1	846
1200	116	14	5	2018-07-14 16:45:00	6	847
1200	122	16	5	2018-07-15 16:45:00	3	848
1200	124	17	7	2018-07-16 16:45:00	6	849
1200	30	14	12	2018-07-17 16:45:00	3	850
1200	122	6	5	2018-07-18 16:45:00	6	851
1200	30	19	2	2018-07-19 16:45:00	6	852
1200	111	14	12	2018-07-20 16:45:00	3	853
1200	117	13	5	2018-07-21 16:45:00	6	854
1200	1	1	7	2018-07-22 16:45:00	6	855
1200	118	13	5	2018-07-23 16:45:00	3	856
1200	123	13	5	2018-07-24 16:45:00	5	857
1200	124	17	5	2018-07-25 16:45:00	6	858
1200	118	16	5	2018-07-26 16:45:00	6	859
1200	1	17	5	2018-07-27 16:45:00	3	860
1200	111	14	5	2018-07-28 16:45:00	6	861
1200	124	1	5	2018-07-29 16:45:00	5	862
1200	116	17	12	2018-07-30 16:45:00	6	863
1200	123	21	5	2018-07-31 16:45:00	6	864
1200	116	16	98	2018-08-01 16:45:00	3	865
1200	122	21	5	2018-08-02 16:45:00	3	866
1200	111	14	12	2018-08-03 16:45:00	3	867
1200	30	1	5	2018-08-04 16:45:00	3	868
1200	121	1	12	2018-08-05 16:45:00	6	869
1200	116	6	98	2018-08-06 16:45:00	6	870
1200	118	17	7	2018-08-07 16:45:00	3	871
1200	117	17	5	2018-08-08 16:45:00	6	872
1200	122	21	2	2018-08-09 16:45:00	6	873
1200	122	15	56	2018-08-10 16:45:00	1	874
1200	122	21	7	2018-08-11 16:45:00	5	875
1200	124	20	5	2018-08-12 16:45:00	6	876
1200	123	18	12	2018-08-13 16:45:00	3	877
1200	1	1	98	2018-08-14 16:45:00	6	878
1200	118	1	12	2018-08-15 16:45:00	5	879
1200	110	6	5	2018-08-16 16:45:00	3	880
1200	123	19	2	2018-08-17 16:45:00	6	881
1200	123	6	98	2018-08-18 16:45:00	6	882
1200	123	18	12	2018-08-19 16:45:00	5	883
1200	121	19	5	2018-08-20 16:45:00	6	884
1200	121	18	12	2018-08-21 16:45:00	6	885
1200	1	14	5	2018-08-22 16:45:00	6	886
1200	121	1	12	2018-08-23 16:45:00	3	887
1200	30	1	98	2018-08-24 16:45:00	1	888
1200	122	19	98	2018-08-25 16:45:00	6	889
1200	121	13	7	2018-08-26 16:45:00	6	890
1200	116	20	5	2018-08-27 16:45:00	1	891
1200	117	1	98	2018-08-28 16:45:00	1	892
1200	30	17	98	2018-08-29 16:45:00	1	893
1200	30	21	98	2018-08-30 16:45:00	6	894
1200	1	1	56	2018-08-31 16:45:00	1	895
1200	111	14	5	2018-09-01 16:45:00	1	896
1200	116	20	98	2018-09-02 16:45:00	1	897
1200	111	18	98	2018-09-03 16:45:00	6	898
1200	121	16	5	2018-09-04 16:45:00	3	899
1200	117	16	7	2018-09-05 16:45:00	3	900
1200	122	1	5	2018-09-06 16:45:00	5	901
1200	1	16	5	2018-09-07 16:45:00	1	902
1200	117	14	5	2018-09-08 16:45:00	6	903
1200	111	16	98	2018-09-09 16:45:00	6	904
1200	30	13	5	2018-09-10 16:45:00	3	905
1200	116	16	98	2018-09-11 16:45:00	1	906
1200	118	13	7	2018-09-12 16:45:00	5	907
1200	110	14	12	2018-09-13 16:45:00	3	908
1200	110	6	7	2018-09-14 16:45:00	6	909
1200	116	20	98	2018-09-15 16:45:00	6	910
1200	117	20	12	2018-09-16 16:45:00	6	911
1200	30	1	5	2018-09-17 16:45:00	3	912
1200	117	19	12	2018-09-18 16:45:00	6	913
1200	124	15	12	2018-09-19 16:45:00	6	914
1200	110	15	12	2018-09-20 16:45:00	3	915
1200	121	21	5	2018-09-21 16:45:00	3	916
1200	123	20	2	2018-09-22 16:45:00	3	917
1200	110	19	2	2018-09-23 16:45:00	5	918
1200	110	13	5	2018-09-24 16:45:00	6	919
1200	118	14	12	2018-09-25 16:45:00	5	920
1200	116	16	98	2018-09-26 16:45:00	3	921
1200	118	14	12	2018-09-27 16:45:00	1	922
1200	121	16	7	2018-09-28 16:45:00	3	923
1200	111	20	12	2018-09-29 16:45:00	1	924
1200	118	21	12	2018-09-30 16:45:00	1	925
1200	110	13	2	2018-10-01 16:45:00	3	926
1200	122	14	12	2018-10-02 16:45:00	3	927
1200	111	20	5	2018-10-03 16:45:00	6	928
1200	30	21	12	2018-10-04 16:45:00	6	929
1200	117	19	5	2018-10-05 16:45:00	1	930
1200	30	20	5	2018-10-06 16:45:00	3	931
1200	110	17	12	2018-10-07 16:45:00	1	932
1200	117	20	7	2018-10-08 16:45:00	5	933
1200	111	16	5	2018-10-09 16:45:00	1	934
1200	123	1	7	2018-10-10 16:45:00	1	935
1200	123	13	5	2018-10-11 16:45:00	5	936
1200	116	17	5	2018-10-12 16:45:00	6	937
1200	111	15	12	2018-10-13 16:45:00	3	938
1200	1	17	5	2018-10-14 16:45:00	6	939
1200	123	6	98	2018-10-15 16:45:00	3	940
1200	122	6	7	2018-10-16 16:45:00	1	941
1200	116	17	2	2018-10-17 16:45:00	3	942
1200	110	16	7	2018-10-18 16:45:00	6	943
1200	122	21	12	2018-10-19 16:45:00	1	944
1200	117	6	98	2018-10-20 16:45:00	6	945
1200	111	14	56	2018-10-21 16:45:00	3	946
1200	30	17	12	2018-10-22 16:45:00	1	947
1200	110	14	7	2018-10-23 16:45:00	3	948
1200	110	14	12	2018-10-24 16:45:00	5	949
1200	30	17	5	2018-10-25 16:45:00	6	950
1200	122	13	5	2018-10-26 16:45:00	6	951
1200	116	19	98	2018-10-27 16:45:00	6	952
1200	121	13	7	2018-10-28 16:45:00	5	953
1200	1	16	5	2018-10-29 16:45:00	1	954
1200	123	21	5	2018-10-30 16:45:00	3	955
1200	118	17	98	2018-10-31 16:45:00	3	956
1200	30	15	5	2018-11-01 16:45:00	3	957
1200	121	15	12	2018-11-02 16:45:00	6	958
1200	110	1	5	2018-11-03 16:45:00	5	959
1200	122	20	5	2018-11-04 16:45:00	3	960
1200	111	21	7	2018-11-05 16:45:00	3	961
1200	111	13	12	2018-11-06 16:45:00	1	962
1200	116	14	12	2018-11-07 16:45:00	5	963
1200	30	16	2	2018-11-08 16:45:00	3	964
1200	118	15	12	2018-11-09 16:45:00	1	965
1200	117	16	98	2018-11-10 16:45:00	1	966
1200	117	20	56	2018-11-11 16:45:00	1	967
1200	110	17	5	2018-11-12 16:45:00	5	968
1200	118	18	5	2018-11-13 16:45:00	6	969
1200	117	17	98	2018-11-14 16:45:00	6	970
1200	30	15	5	2018-11-15 16:45:00	3	971
1200	118	19	12	2018-11-16 16:45:00	5	972
1200	122	20	5	2018-11-17 16:45:00	3	973
1200	30	20	7	2018-11-18 16:45:00	3	974
1200	110	16	5	2018-11-19 16:45:00	3	975
1200	122	16	5	2018-11-20 16:45:00	3	976
1200	111	16	56	2018-11-21 16:45:00	6	977
1200	122	19	7	2018-11-22 16:45:00	5	978
1200	123	21	5	2018-11-23 16:45:00	3	979
1200	110	17	7	2018-11-24 16:45:00	3	980
1200	111	13	98	2018-11-25 16:45:00	3	981
1200	111	18	98	2018-11-26 16:45:00	6	982
1200	116	13	2	2018-11-27 16:45:00	1	983
1200	110	15	7	2018-11-28 16:45:00	5	984
1200	117	16	12	2018-11-29 16:45:00	3	985
1200	124	20	5	2018-11-30 16:45:00	5	986
1200	121	16	7	2018-12-01 16:45:00	3	987
1200	122	17	98	2018-12-02 16:45:00	1	988
1200	123	13	7	2018-12-03 16:45:00	1	989
1200	116	1	12	2018-12-04 16:45:00	6	990
1200	118	21	98	2018-12-05 16:45:00	1	991
1200	30	18	56	2018-12-06 16:45:00	6	992
1200	111	13	12	2018-12-07 16:45:00	3	993
1200	111	18	2	2018-12-08 16:45:00	5	994
1200	111	16	5	2018-12-09 16:45:00	5	995
1200	122	21	56	2018-05-10 16:45:00	6	996
1200	111	16	12	2018-05-11 16:45:00	6	997
1200	117	19	5	2018-05-12 16:45:00	5	998
1200	110	20	56	2018-05-13 16:45:00	6	999
1200	122	21	7	2018-05-14 16:45:00	1	1000
1200	116	1	7	2018-05-15 16:45:00	6	1001
1200	1	16	12	2018-05-16 16:45:00	3	1002
1200	110	14	7	2018-05-17 16:45:00	3	1003
1200	118	16	5	2018-05-18 16:45:00	6	1004
1200	110	6	7	2018-05-19 16:45:00	5	1005
1200	122	17	12	2018-05-20 16:45:00	3	1006
1200	116	20	5	2018-05-21 16:45:00	1	1007
1200	121	13	7	2018-05-22 16:45:00	1	1008
1200	118	17	5	2018-05-23 16:45:00	6	1009
1200	122	6	12	2018-05-24 16:45:00	3	1010
1200	110	1	12	2018-05-25 16:45:00	1	1011
1200	116	18	12	2018-05-26 16:45:00	5	1012
1200	1	15	12	2018-05-27 16:45:00	6	1013
1200	121	19	5	2018-05-28 16:45:00	1	1014
1200	117	16	5	2018-05-29 16:45:00	1	1015
1200	122	13	5	2018-05-30 16:45:00	3	1016
1200	123	20	12	2018-05-31 16:45:00	6	1017
1200	122	14	2	2018-06-01 16:45:00	3	1018
1200	110	20	5	2018-06-02 16:45:00	5	1019
1200	122	13	12	2018-06-03 16:45:00	6	1020
1200	110	19	5	2018-06-04 16:45:00	3	1021
1200	117	19	7	2018-06-05 16:45:00	6	1022
1200	30	17	56	2018-06-06 16:45:00	5	1023
1200	123	1	5	2018-06-07 16:45:00	6	1024
1200	123	21	12	2018-06-08 16:45:00	6	1025
1200	118	13	5	2018-06-09 16:45:00	1	1026
1200	111	14	5	2018-06-10 16:45:00	5	1027
1200	30	18	98	2018-06-11 16:45:00	6	1028
1200	121	16	2	2018-06-12 16:45:00	1	1029
1200	124	13	12	2018-06-13 16:45:00	1	1030
1200	123	20	12	2018-06-14 16:45:00	5	1031
1200	123	6	98	2018-06-15 16:45:00	6	1032
1200	123	1	12	2018-06-16 16:45:00	3	1033
1200	118	17	5	2018-06-17 16:45:00	6	1034
1200	30	19	98	2018-06-18 16:45:00	3	1035
1200	110	13	12	2018-06-19 16:45:00	3	1036
1200	121	18	7	2018-06-20 16:45:00	6	1037
1200	117	15	98	2018-06-21 16:45:00	3	1038
1200	123	14	5	2018-06-22 16:45:00	6	1039
1200	110	20	5	2018-06-23 16:45:00	6	1040
1200	123	21	56	2018-06-24 16:45:00	3	1041
1200	117	17	5	2018-06-25 16:45:00	3	1042
1200	111	20	98	2018-06-26 16:45:00	5	1043
1200	111	14	5	2018-06-27 16:45:00	5	1044
1200	118	17	5	2018-06-28 16:45:00	5	1045
1200	110	15	7	2018-06-29 16:45:00	6	1046
1200	122	13	12	2018-06-30 16:45:00	3	1047
1200	111	21	12	2018-07-01 16:45:00	1	1048
1200	122	21	5	2018-07-02 16:45:00	3	1049
1200	117	19	98	2018-07-03 16:45:00	6	1050
1200	118	16	12	2018-07-04 16:45:00	6	1051
1200	123	14	98	2018-07-05 16:45:00	3	1052
1200	30	15	12	2018-07-06 16:45:00	6	1053
1200	118	14	7	2018-07-07 16:45:00	3	1054
1200	1	19	98	2018-07-08 16:45:00	3	1055
1200	110	14	12	2018-07-09 16:45:00	3	1056
1200	117	21	98	2018-07-10 16:45:00	6	1057
1200	110	16	12	2018-07-11 16:45:00	1	1058
1200	121	21	12	2018-07-12 16:45:00	6	1059
1200	118	17	5	2018-07-13 16:45:00	6	1060
1200	121	17	7	2018-07-14 16:45:00	3	1061
1200	30	19	12	2018-07-15 16:45:00	1	1062
1200	117	1	12	2018-07-16 16:45:00	5	1063
1200	121	19	12	2018-07-17 16:45:00	1	1064
1200	121	1	12	2018-07-18 16:45:00	3	1065
1200	117	16	7	2018-07-19 16:45:00	1	1066
1200	111	15	98	2018-07-20 16:45:00	6	1067
1200	121	20	7	2018-07-21 16:45:00	3	1068
1200	116	19	5	2018-07-22 16:45:00	3	1069
1200	116	6	5	2018-07-23 16:45:00	6	1070
1200	30	21	5	2018-07-24 16:45:00	6	1071
1200	110	6	12	2018-07-25 16:45:00	3	1072
1200	30	19	5	2018-07-26 16:45:00	6	1073
1200	1	21	5	2018-07-27 16:45:00	3	1074
1200	1	16	56	2018-07-28 16:45:00	6	1075
1200	30	15	5	2018-07-29 16:45:00	3	1076
1200	123	19	98	2018-07-30 16:45:00	3	1077
1200	122	16	12	2018-07-31 16:45:00	5	1078
1200	111	17	98	2018-08-01 16:45:00	6	1079
1200	110	14	2	2018-08-02 16:45:00	6	1080
1200	116	14	7	2018-08-03 16:45:00	3	1081
1200	117	21	5	2018-08-04 16:45:00	3	1082
1200	111	17	5	2018-08-05 16:45:00	3	1083
1200	122	16	98	2018-08-06 16:45:00	6	1084
1200	30	17	12	2018-08-07 16:45:00	5	1085
1200	122	20	98	2018-08-08 16:45:00	5	1086
1200	116	13	98	2018-08-09 16:45:00	5	1087
1200	1	20	5	2018-08-10 16:45:00	3	1088
1200	117	21	5	2018-08-11 16:45:00	6	1089
1200	121	15	7	2018-08-12 16:45:00	5	1090
1200	121	17	7	2018-08-13 16:45:00	3	1091
1200	122	6	5	2018-08-14 16:45:00	5	1092
1200	118	6	98	2018-08-15 16:45:00	3	1093
1200	122	17	7	2018-08-16 16:45:00	1	1094
1200	123	1	2	2018-08-17 16:45:00	5	1095
1200	123	19	7	2018-08-18 16:45:00	3	1096
1200	118	21	5	2018-08-19 16:45:00	3	1097
1200	30	13	5	2018-08-20 16:45:00	6	1098
1200	123	17	7	2018-08-21 16:45:00	6	1099
1200	118	13	5	2018-08-22 16:45:00	1	1100
1200	117	13	12	2018-08-23 16:45:00	3	1101
1200	122	19	12	2018-08-24 16:45:00	6	1102
1200	122	13	98	2018-08-25 16:45:00	6	1103
1200	30	21	5	2018-08-26 16:45:00	6	1104
1200	122	15	12	2018-08-27 16:45:00	5	1105
1200	110	1	98	2018-08-28 16:45:00	6	1106
1200	110	18	7	2018-08-29 16:45:00	1	1107
1200	117	21	2	2018-08-30 16:45:00	6	1108
1200	111	13	5	2018-08-31 16:45:00	1	1109
1200	111	17	12	2018-09-01 16:45:00	1	1110
1200	123	17	98	2018-09-02 16:45:00	1	1111
1200	118	21	98	2018-09-03 16:45:00	3	1112
1200	30	14	5	2018-09-04 16:45:00	6	1113
1200	121	21	5	2018-09-05 16:45:00	3	1114
1200	123	17	7	2018-09-06 16:45:00	3	1115
1200	117	16	5	2018-09-07 16:45:00	6	1116
1200	122	15	98	2018-09-08 16:45:00	5	1117
1200	121	17	56	2018-09-09 16:45:00	6	1118
1200	30	19	98	2018-09-10 16:45:00	6	1119
1200	110	13	12	2018-09-11 16:45:00	6	1120
1200	1	6	7	2018-09-12 16:45:00	6	1121
1200	123	17	56	2018-09-13 16:45:00	6	1122
1200	124	16	5	2018-09-14 16:45:00	3	1123
1200	110	15	56	2018-09-15 16:45:00	3	1124
1200	117	14	12	2018-09-16 16:45:00	1	1125
1200	111	16	98	2018-09-17 16:45:00	3	1126
1200	30	13	98	2018-09-18 16:45:00	6	1127
1200	121	14	7	2018-09-19 16:45:00	6	1128
1200	121	19	12	2018-09-20 16:45:00	6	1129
1200	111	17	12	2018-09-21 16:45:00	3	1130
1200	122	17	5	2018-09-22 16:45:00	3	1131
1200	121	17	12	2018-09-23 16:45:00	1	1132
1200	30	15	5	2018-09-24 16:45:00	3	1133
1200	118	21	5	2018-09-25 16:45:00	6	1134
1200	111	16	7	2018-09-26 16:45:00	5	1135
1200	123	14	98	2018-09-27 16:45:00	6	1136
1200	116	15	5	2018-09-28 16:45:00	3	1137
1200	121	14	98	2018-09-29 16:45:00	3	1138
1200	30	15	12	2018-09-30 16:45:00	6	1139
1200	121	19	12	2018-10-01 16:45:00	6	1140
1200	123	1	5	2018-10-02 16:45:00	3	1141
1200	124	14	2	2018-10-03 16:45:00	3	1142
1200	123	16	7	2018-10-04 16:45:00	5	1143
1200	124	21	12	2018-10-05 16:45:00	3	1144
1200	30	14	98	2018-10-06 16:45:00	6	1145
1200	111	13	5	2018-10-07 16:45:00	3	1146
1200	110	6	2	2018-10-08 16:45:00	3	1147
1200	121	21	5	2018-10-09 16:45:00	6	1148
1200	1	16	56	2018-10-10 16:45:00	5	1149
1200	123	18	7	2018-10-11 16:45:00	5	1150
1200	116	17	98	2018-10-12 16:45:00	3	1151
1200	117	1	5	2018-10-13 16:45:00	6	1152
1200	121	16	7	2018-10-14 16:45:00	5	1153
1200	121	17	5	2018-10-15 16:45:00	3	1154
1200	110	1	98	2018-10-16 16:45:00	3	1155
1200	1	21	12	2018-10-17 16:45:00	1	1156
1200	30	20	2	2018-10-18 16:45:00	1	1157
1200	122	16	12	2018-10-19 16:45:00	1	1158
1200	121	14	7	2018-10-20 16:45:00	1	1159
1200	121	20	98	2018-10-21 16:45:00	3	1160
1200	30	6	7	2018-10-22 16:45:00	6	1161
1200	110	13	5	2018-10-23 16:45:00	1	1162
1200	118	20	12	2018-10-24 16:45:00	6	1163
1200	121	16	5	2018-10-25 16:45:00	6	1164
1200	30	14	12	2018-10-26 16:45:00	5	1165
1200	123	19	56	2018-10-27 16:45:00	6	1166
1200	117	16	98	2018-10-28 16:45:00	1	1167
1200	30	17	5	2018-10-29 16:45:00	3	1168
1200	118	20	56	2018-10-30 16:45:00	1	1169
1200	116	1	5	2018-10-31 16:45:00	6	1170
1200	123	14	7	2018-11-01 16:45:00	6	1171
1200	123	21	7	2018-11-02 16:45:00	5	1172
1200	110	1	12	2018-11-03 16:45:00	6	1173
1200	123	20	5	2018-11-04 16:45:00	3	1174
1200	30	21	7	2018-11-05 16:45:00	1	1175
1200	117	21	7	2018-11-06 16:45:00	5	1176
1200	121	16	12	2018-11-07 16:45:00	5	1177
1200	116	6	98	2018-11-08 16:45:00	3	1178
1200	110	1	98	2018-11-09 16:45:00	6	1179
1200	30	6	5	2018-11-10 16:45:00	6	1180
1200	30	16	5	2018-11-11 16:45:00	1	1181
1200	30	16	7	2018-11-12 16:45:00	3	1182
1200	111	14	7	2018-11-13 16:45:00	6	1183
1200	118	19	12	2018-11-14 16:45:00	3	1184
1200	124	16	5	2018-11-15 16:45:00	3	1185
1200	116	21	5	2018-11-16 16:45:00	5	1186
1200	1	15	5	2018-11-17 16:45:00	1	1187
1200	111	6	98	2018-11-18 16:45:00	3	1188
1200	117	21	12	2018-11-19 16:45:00	6	1189
1200	111	19	98	2018-11-20 16:45:00	3	1190
1200	116	6	2	2018-11-21 16:45:00	6	1191
1200	121	17	2	2018-11-22 16:45:00	6	1192
1200	122	15	2	2018-11-23 16:45:00	1	1193
1200	30	17	5	2018-11-24 16:45:00	1	1194
1200	122	19	7	2018-11-25 16:45:00	1	1195
1200	121	6	12	2018-11-26 16:45:00	1	1196
1200	123	20	5	2018-11-27 16:45:00	1	1197
1200	118	15	5	2018-11-28 16:45:00	5	1198
1200	116	14	98	2018-11-29 16:45:00	1	1199
1200	30	19	98	2018-11-30 16:45:00	5	1200
1200	123	19	56	2018-12-01 16:45:00	5	1201
1200	116	1	5	2018-12-02 16:45:00	1	1202
1200	122	13	2	2018-12-03 16:45:00	3	1203
1200	118	17	5	2018-12-04 16:45:00	3	1204
1200	116	1	5	2018-12-05 16:45:00	6	1205
1200	116	1	98	2018-12-06 16:45:00	6	1206
1200	121	16	5	2018-12-07 16:45:00	6	1207
1200	1	16	5	2018-12-08 16:45:00	5	1208
1200	30	14	12	2018-12-09 16:45:00	3	1209
1200	111	17	3	2018-05-31 10:00:00	1	1212
\.


--
-- Data for Name: occupancy; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.occupancy (seat_id, user_id, flight_id) FROM stdin;
32	3	110
37	3	110
38	3	110
369	3	118
370	3	118
371	3	118
372	3	118
374	3	118
375	3	118
376	3	118
377	3	118
378	3	118
379	3	118
380	3	118
381	3	118
382	3	118
384	3	118
328	3	117
329	3	117
330	3	117
331	3	117
332	3	117
333	3	117
334	3	117
335	3	117
336	3	117
337	3	117
\.


--
-- Data for Name: planes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.planes (plane_id, seats_num, company, plane_type, flight_id) FROM stdin;
6	40	МАУ	Airbus A320-211	1
1	40	Utair	Airbus A320-211	110
15	40	Победа	Airbus A320-211	117
16	40	Победа	Airbus A320-211	118
13	40	S7	Airbus A320-211	30
19	40	Аэрофлот	Airbus A320-211	122
21	40	Аэрофлот	Airbus A320-211	123
18	40	Ural Airlines	Airbus A320-211	121
17	40	Победа	Airbus A320-211	\N
14	40	Победа	Airbus A320-211	\N
20	40	Аэрофлот	Airbus A320-211	\N
\.


--
-- Data for Name: seats; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.seats (seat_id, plane_id, serial_number_in_plane) FROM stdin;
26	1	1
288	14	1
289	14	2
290	14	3
291	14	4
292	14	5
293	14	6
294	14	7
295	14	8
296	14	9
297	14	10
298	14	11
299	14	12
300	14	13
301	14	14
302	14	15
303	14	16
304	14	17
305	14	18
306	14	19
307	14	20
308	14	21
309	14	22
310	14	23
311	14	24
312	14	25
313	14	26
314	14	27
315	14	28
316	14	29
317	14	30
318	14	31
319	14	32
320	14	33
321	14	34
322	14	35
323	14	36
324	14	37
325	14	38
326	14	39
327	14	40
328	15	1
329	15	2
330	15	3
331	15	4
332	15	5
333	15	6
334	15	7
335	15	8
336	15	9
337	15	10
338	15	11
339	15	12
340	15	13
341	15	14
342	15	15
343	15	16
344	15	17
345	15	18
346	15	19
347	15	20
348	15	21
349	15	22
350	15	23
351	15	24
352	15	25
353	15	26
354	15	27
355	15	28
356	15	29
357	15	30
358	15	31
359	15	32
360	15	33
361	15	34
362	15	35
363	15	36
364	15	37
365	15	38
366	15	39
367	15	40
368	16	1
369	16	2
370	16	3
371	16	4
372	16	5
373	16	6
374	16	7
375	16	8
376	16	9
377	16	10
378	16	11
379	16	12
380	16	13
381	16	14
382	16	15
383	16	16
384	16	17
385	16	18
386	16	19
387	16	20
388	16	21
389	16	22
390	16	23
391	16	24
392	16	25
393	16	26
394	16	27
395	16	28
396	16	29
397	16	30
398	16	31
399	16	32
400	16	33
401	16	34
402	16	35
403	16	36
404	16	37
405	16	38
406	16	39
407	16	40
408	17	1
409	17	2
410	17	3
411	17	4
412	17	5
413	17	6
414	17	7
415	17	8
416	17	9
417	17	10
418	17	11
419	17	12
420	17	13
421	17	14
422	17	15
423	17	16
424	17	17
425	17	18
426	17	19
427	17	20
428	17	21
429	17	22
430	17	23
431	17	24
432	17	25
433	17	26
434	17	27
435	17	28
436	17	29
437	17	30
438	17	31
439	17	32
440	17	33
441	17	34
442	17	35
443	17	36
444	17	37
445	17	38
446	17	39
447	17	40
32	1	3
37	1	4
31	1	2
38	1	5
448	18	1
449	18	2
450	18	3
451	18	4
452	18	5
453	18	6
454	18	7
455	18	8
456	18	9
457	18	10
458	18	11
459	18	12
460	18	13
461	18	14
462	18	15
463	18	16
464	18	17
465	18	18
466	18	19
467	18	20
468	18	21
469	18	22
470	18	23
471	18	24
472	18	25
473	18	26
474	18	27
475	18	28
476	18	29
477	18	30
478	18	31
479	18	32
480	18	33
481	18	34
482	18	35
483	18	36
484	18	37
485	18	38
486	18	39
487	18	40
488	19	1
489	19	2
490	19	3
491	19	4
492	19	5
493	19	6
494	19	7
495	19	8
496	19	9
497	19	10
498	19	11
499	19	12
500	19	13
501	19	14
502	19	15
248	13	1
249	13	2
250	13	3
251	13	4
252	13	5
253	13	6
254	13	7
255	13	8
256	13	9
257	13	10
258	13	11
259	13	12
260	13	13
261	13	14
262	13	15
263	13	16
264	13	17
265	13	18
266	13	19
267	13	20
268	13	21
269	13	22
270	13	23
271	13	24
272	13	25
273	13	26
274	13	27
275	13	28
276	13	29
277	13	30
278	13	31
279	13	32
280	13	33
281	13	34
282	13	35
283	13	36
284	13	37
285	13	38
286	13	39
287	13	40
503	19	16
504	19	17
505	19	18
506	19	19
507	19	20
508	19	21
509	19	22
510	19	23
511	19	24
512	19	25
513	19	26
514	19	27
515	19	28
516	19	29
517	19	30
518	19	31
519	19	32
520	19	33
521	19	34
522	19	35
523	19	36
524	19	37
525	19	38
526	19	39
527	19	40
528	20	1
529	20	2
530	20	3
531	20	4
532	20	5
533	20	6
534	20	7
535	20	8
536	20	9
537	20	10
538	20	11
539	20	12
540	20	13
541	20	14
542	20	15
543	20	16
544	20	17
545	20	18
546	20	19
547	20	20
548	20	21
549	20	22
550	20	23
551	20	24
552	20	25
553	20	26
554	20	27
555	20	28
556	20	29
557	20	30
558	20	31
559	20	32
560	20	33
561	20	34
562	20	35
563	20	36
564	20	37
565	20	38
566	20	39
567	20	40
568	21	1
569	21	2
570	21	3
571	21	4
572	21	5
573	21	6
574	21	7
575	21	8
576	21	9
577	21	10
578	21	11
579	21	12
580	21	13
581	21	14
582	21	15
583	21	16
584	21	17
585	21	18
586	21	19
587	21	20
588	21	21
589	21	22
590	21	23
591	21	24
592	21	25
593	21	26
594	21	27
595	21	28
596	21	29
597	21	30
598	21	31
599	21	32
600	21	33
601	21	34
602	21	35
603	21	36
604	21	37
605	21	38
606	21	39
607	21	40
\.


--
-- Data for Name: tariff; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tariff (tariff_id, price, large_luggage, food) FROM stdin;
1	1200	f	f
3	2500	t	f
6	2600	t	t
5	1400	f	t
\.


--
-- Data for Name: tickets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tickets (ticket_id, tariff_id, seat_id, plane_id, flight_id, user_id) FROM stdin;
211	3	32	1	110	3
212	3	37	1	110	3
213	3	38	1	110	3
168	6	369	16	118	3
169	6	370	16	118	3
170	6	371	16	118	3
171	6	372	16	118	3
173	6	374	16	118	3
174	6	375	16	118	3
175	6	376	16	118	3
176	6	377	16	118	3
177	6	378	16	118	3
178	6	379	16	118	3
179	6	380	16	118	3
180	6	381	16	118	3
181	6	382	16	118	3
183	6	384	16	118	3
185	6	328	15	117	3
186	6	329	15	117	3
187	6	330	15	117	3
188	6	331	15	117	3
189	6	332	15	117	3
190	6	333	15	117	3
191	6	334	15	117	3
192	6	335	15	117	3
193	6	336	15	117	3
194	6	337	15	117	3
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (user_id, name, login, surname, passport_num, phone_number, status, password) FROM stdin;
4	kirill	\N	akimov	en1213	\N	user	\N
5	kir	\N	akimmmm	en000000	\N	user	\N
6	aaa	\N	ccc	en77	\N	user	\N
13	a	ff	d	er56	\N	user	aaa
30	admin	admin	admin	qwerty	\N	admin	admin
43	vasya	asdmlld@.com	ivanov	en234	+728499	user	21313
48	kir	at	akim	en	+79856847090	user	at
3	kirill	ak	b	en969952	03	user	123
\.


--
-- Name: flights_flight_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.flights_flight_id_seq', 126, true);


--
-- Name: logsforbudget_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.logsforbudget_log_id_seq', 1214, true);


--
-- Name: planes_plane_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.planes_plane_id_seq', 22, true);


--
-- Name: seats_seat_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.seats_seat_id_seq', 607, true);


--
-- Name: tariff_tariff_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.tariff_tariff_id_seq', 6, true);


--
-- Name: tickets_ticket_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.tickets_ticket_id_seq', 218, true);


--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_user_id_seq', 85596, true);


--
-- Name: flights flights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flights
    ADD CONSTRAINT flights_pkey PRIMARY KEY (flight_id);


--
-- Name: logsforbudget logsforbudget_log_id_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logsforbudget
    ADD CONSTRAINT logsforbudget_log_id_pk PRIMARY KEY (log_id);


--
-- Name: planes planes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT planes_pkey PRIMARY KEY (plane_id);


--
-- Name: seats seats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seats
    ADD CONSTRAINT seats_pkey PRIMARY KEY (seat_id);


--
-- Name: tariff tariff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tariff
    ADD CONSTRAINT tariff_pkey PRIMARY KEY (tariff_id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (ticket_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: flights_departure_destination_flight_date_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX flights_departure_destination_flight_date_uindex ON public.flights USING btree (departure, destination, flight_date);


--
-- Name: idx_flight_depart; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_flight_depart ON public.flights USING btree (departure, destination);


--
-- Name: idx_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_name ON public.users USING btree (login);


--
-- Name: occupancy_seat_id_flight_id_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX occupancy_seat_id_flight_id_uindex ON public.occupancy USING btree (seat_id, flight_id);


--
-- Name: planes_flight_id_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX planes_flight_id_uindex ON public.planes USING btree (flight_id);


--
-- Name: tickets_seat_id_flight_id_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tickets_seat_id_flight_id_uindex ON public.tickets USING btree (seat_id, flight_id);


--
-- Name: users_login_password_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_login_password_uindex ON public.users USING btree (login, password);


--
-- Name: users_passport_num_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_passport_num_uindex ON public.users USING btree (passport_num);


--
-- Name: tickets t_add_occupancy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_add_occupancy AFTER INSERT ON public.tickets FOR EACH ROW EXECUTE PROCEDURE public.add_to_occupancy();


--
-- Name: planes t_add_plane; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_add_plane AFTER INSERT ON public.planes FOR EACH ROW EXECUTE PROCEDURE public.add_to_seats();


--
-- Name: tickets t_add_to_logs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_add_to_logs AFTER INSERT ON public.tickets FOR EACH ROW EXECUTE PROCEDURE public.add_to_logs();


--
-- Name: tickets t_del_occupancy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_del_occupancy BEFORE DELETE ON public.tickets FOR EACH ROW EXECUTE PROCEDURE public.del_from_occupancy();


--
-- Name: planes t_del_plane; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_del_plane BEFORE DELETE ON public.planes FOR EACH ROW EXECUTE PROCEDURE public.del_seats();


--
-- Name: occupancy occupancy_flights_flight_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_flights_flight_id_fk FOREIGN KEY (flight_id) REFERENCES public.flights(flight_id) ON DELETE CASCADE;


--
-- Name: occupancy occupancy_seat_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_seat_id_fkey FOREIGN KEY (seat_id) REFERENCES public.seats(seat_id);


--
-- Name: occupancy occupancy_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.occupancy
    ADD CONSTRAINT occupancy_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: planes planes_flights_flight_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT planes_flights_flight_id_fk FOREIGN KEY (flight_id) REFERENCES public.flights(flight_id);


--
-- Name: seats seats_plane_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seats
    ADD CONSTRAINT seats_plane_id_fkey FOREIGN KEY (plane_id) REFERENCES public.planes(plane_id);


--
-- Name: tickets tickets_id_flight_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_id_flight_fkey FOREIGN KEY (flight_id) REFERENCES public.flights(flight_id) ON DELETE CASCADE;


--
-- Name: tickets tickets_plane_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_plane_id_fkey FOREIGN KEY (plane_id) REFERENCES public.planes(plane_id);


--
-- Name: tickets tickets_seat_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_seat_id_fkey FOREIGN KEY (seat_id) REFERENCES public.seats(seat_id);


--
-- Name: tickets tickets_tariff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_tariff_id_fkey FOREIGN KEY (tariff_id) REFERENCES public.tariff(tariff_id);


--
-- Name: tickets tickets_users_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_users_user_id_fk FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- PostgreSQL database dump complete
--

