#!/usr/bin/env python
# -*- coding: utf-8 -*-
import cmd, psycopg2
import itertools


def dict_factory(cursor, row):
    d = {}
    for idx, col in enumerate(cursor.description):
        d[col[0]] = row[idx]
    return d


class Cli(cmd.Cmd):
    def __init__(self):
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
        # self.row_factory=dict_factory
        cmd.Cmd.__init__(self)
        self.prompt = "> "
        self.intro = "Добро пожаловать\nДля справки наберите 'help'"
        self.doc_header = "Доступные команды (для справки по конкретной команде наберите 'help _команда_')"


    # def complete_(self, text, state):


    def do_hello(self, args):
        """hello - выводит 'hello world' на экран"""
        print("hello world")

    def do_create_user(self, args):
        """create_user name surname- создает пользователя с именем name surname"""
        try:
            self.cursor = self.connect.cursor()
            name_surname = args.split()
            if (len(name_surname)!=2):
                raise Exception("Wrong number of arguments\n")
            pasport = input("Введите серию/номер паспорта без пробелов (заглавными буквами)\n")

            # check if user exists
            self.cursor.execute("SELECT * from users WHERE name=%s AND surname=%s AND passport_num=%s",
                                (name_surname[0],name_surname[1],pasport))
            user_id = self.cursor.fetchone()
            if user_id:
                raise Exception("USER ALREADY EXISTS")
            # end of check


            telephon = input("Введите номер телефона (необязательно)\n")
            if telephon.isnumeric():
                self.cursor.execute(
                    "INSERT INTO users (name, surname,passport_num,phone_number) VALUES (%s,%s,%s,%s)",
                    (name_surname[0], name_surname[1], pasport, telephon))
            else:
                self.cursor.execute(
                    "INSERT INTO users (name, surname,passport_num) VALUES (%s,%s,%s)",
                    (name_surname[0], name_surname[1], pasport))
            print('OK!')
            self.connect.commit()
        except Exception as e:
            self.connect.rollback()
            print(e)

    def do_buy_ticket(self, args):
        """allow you buy tickets, args is name, surname, passport"""
        try:
            self.cursor = self.connect.cursor()
            user_ident = args.split()

            # check if user exists
            self.cursor.execute("SELECT * from users WHERE name=%s AND surname=%s AND passport_num=%s",
                                user_ident)
            user_id = self.cursor.fetchone()
            if not user_id:
                raise Exception("USER NOT EXISTS")
            # end of check

            print("Выберите направление:\n")
            self.cursor.execute("SELECT departure, destination from flights")
            for row in self.cursor.fetchall():
                print('Departure from: {0[0]}, destination is: {0[1]}\n'.format(row))
            dep = input("Введите departure\n")
            dest = input("Введите destination\n")

            # ЗДЕСЬ ДОЛЖНА БЫТЬ ПРОВЕРКА НА КОРРЕКТНОСТЬ ВВОДА!!!

            # вытягиваем plane_id с интересующего нас рейса
            self.cursor.execute("SELECT plane_id from flights WHERE departure = %s AND destination = %s", (dep, dest))
            plane_id = self.cursor.fetchone()

            # достаем свободные места в этом самолете plane_id
            self.cursor.execute(
                """SELECT S.seat_id, S.tariff_id from seats S 
            LEFT JOIN occupancy O ON S.seat_id = O.seat_id 
            WHERE O.seat_id is NULL AND plane_id=%s""", plane_id)
            for row in self.cursor.fetchall():
                print('Number of seat: {0[0]}, tariff code: {0[1]}\n'.format(row))
            print("According to the table of tariffs\n")

            # делае расшифровку тарифов
            self.cursor.execute("""SELECT DISTINCT t.tariff_id, t.price,t.large_luggage
            FROM tariff t INNER JOIN (SELECT
                           S.seat_id,
                           S.tariff_id,
                           S.plane_id
                         FROM seats S LEFT JOIN occupancy O ON S.seat_id = O.seat_id
                         WHERE O.seat_id IS NULL AND plane_id = %s) AS r ON t.tariff_id=r.tariff_id""", plane_id)
            for row in self.cursor.fetchall():
                print('tariff code: {0[0]}, price: {0[1]}, availability of large luggage: {0[2]}\n'.format(row))

            # получаем flight_id
            self.cursor.execute("SELECT flight_id from flights WHERE departure = %s AND destination = %s", (dep, dest))
            flight_id = self.cursor.fetchone()

            # вводим место согласно представленным данным
            seat_id = input("Введите номер места: ")
            self.cursor.execute("INSERT INTO occupancy (seat_id, user_id,flight_id) VALUES (%s,%s,%s)",
                                (seat_id, user_id[0], flight_id[0]))
            self.connect.commit()
            print("\nБилеты куплены!")

        except Exception as e:
            self.connect.rollback()
            print(e)

    def __del__(self):
        self.cursor.close()
        self.connect.close()

    def default(self, line):
        print("Несуществующая команда")


if __name__ == "__main__":
    cli = Cli()
    try:
        cli.cmdloop()
    except KeyboardInterrupt:
        print("завершение сеанса...")
