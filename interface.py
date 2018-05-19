#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# work with windows
import sys
import linecache

from PyQt5.QtCore import Qt, QDateTime, QDate, QTimer, QTime
from PyQt5.QtWidgets import QApplication, QMessageBox, QTabWidget
from PyQt5 import uic
import psycopg2
import re

Ui_WindowLogin, QLogIn = uic.loadUiType('login.ui')
Ui_MainWindow, QMainWindow = uic.loadUiType('mainwindow.ui')
Ui_WindowRegistration, QRegistration = uic.loadUiType('registration.ui')
Ui_WindowTicket, QTicket = uic.loadUiType('ticket.ui')
Ui_WindowChangeInfo, QChangeInfo = uic.loadUiType('changeinfo.ui')
Ui_Profile, QProfile = uic.loadUiType('profile.ui')
Ui_Admin, QAdmin = uic.loadUiType('adminwindow.ui')
Ui_WindowBuyTicket, QBuyTicket = uic.loadUiType('buyticket.ui')


class ErrorMessage:
    def __init__(self, title="", message=""):
        msgBox = QMessageBox()
        msgBox.setIcon(QMessageBox.Warning)
        msgBox.setWindowTitle(title)
        msgBox.setText(message)
        msgBox.setStandardButtons(QMessageBox.Ok)
        msgBox.exec_()


class LogInWindow(QLogIn):
    def __init__(self, parent=None):

        QLogIn.__init__(self, parent)

        self.ui = Ui_WindowLogin()
        self.ui.setupUi(self)

        self.ui.sign_up_button.clicked.connect(
            lambda: self.parent().replace_with(RegistrationWindow())
        )
        self.ui.sign_in_button.clicked.connect(self.__execute_login)

    def __del__(self):
        self.ui = None

    def __execute_login(self):
        try:
            login = self.ui.line_login.text()
            password = self.ui.line_password.text()

            ConnectionDB.cursor.execute(
                """SELECT user_id, name ,surname, login , status, passport_num, 
                  phone_number,password 
                  from users WHERE login=%s AND password=%s""",
                (login, password))
            user = ConnectionDB.cursor.fetchone()
            if not user:
                ErrorMessage('Warning', 'Invalid Username And Password')
                raise Exception("USER NOT EXISTS")

            # creat instance of user in current session
            Current_User.set(user)

            # !!!!!!!!
            if Current_User.status == "admin":
                self.parent().replace_with(AdminWindow())
            else:
                self.parent().replace_with(ProfileWindow())

        # except Exception as e:
        except:
            ConnectionDB.connect.rollback()
            # print(e)
            PrintException()

    # обработка нажатия на "enter"
    def keyPressEvent(self, event):
        if self.ui.line_login.text() == "":
            return
        if self.ui.line_password.text() == "":
            return
        if event.key() == Qt.Key_Return:
            self.__execute_login()


class ProfileWindow(QProfile):
    def __init__(self, parent=None):
        QProfile.__init__(self, parent)
        self.ui = Ui_Profile()
        self.ui.setupUi(self)

        self.ui.button_buy.clicked.connect(lambda: self.parent().replace_with(BuyTicketWindow()))
        self.ui.button_change.clicked.connect(lambda: self.parent().replace_with(ChangeInfoWindow()))
        self.ui.backButton.clicked.connect(lambda: self.parent().replace_with(LogInWindow()))

        # display user info
        self.ui.label_name.setText(Current_User.name if Current_User.name != "" else "[No data]")
        self.ui.label_surname.setText(Current_User.surname if Current_User.name != "" else "[No data]")
        self.ui.label_login.setText(Current_User.login if Current_User.login != "" else "[No data]")
        self.ui.label_password.setText(Current_User.password if Current_User.password != "" else "[No data]")
        self.ui.label_passport.setText(Current_User.passport_num if Current_User.passport_num != "" else "[No data]")
        self.ui.label_phone.setText(Current_User.phone_number if Current_User.phone_number != "" else "[No data]")

        # combobox: watch a list of bought tickets
        # ConnectionDB.cursor.execute("SELECT ticket_id from tickets WHERE user_id=%s", (Current_User.user_id,))
        # tickets = ConnectionDB.cursor.fetchall()
        # for ticket in result:
        ConnectionDB.cursor.execute(
            """SELECT ticket_id, departure,destination FROM flights LEFT JOIN tickets USING (flight_id) WHERE user_id=%s""",
            (Current_User.user_id,))
        tick_inf = ConnectionDB.cursor.fetchall()
        for ticket_info in tick_inf:
            self.ui.comboBox_tickets.addItem(str(ticket_info[0]) + ": " + str(ticket_info[1]) +
                                             " -> " + str(ticket_info[2]))

        self.ui.comboBox_tickets.activated[str].connect(self.show_ticket)

    def show_ticket(self, text):
        text = re.sub(r':.*', '', text)
        Current_Ticket.set(int(text))
        self.parent().replace_with(TicketWindow())

    def __del__(self):
        self.ui = None


class RegistrationWindow(QRegistration):
    def __init__(self, parent=None):
        QRegistration.__init__(self, parent)

        self.ui = Ui_WindowRegistration()
        self.ui.setupUi(self)

        self.ui.sign_up_button.clicked.connect(self.__execute_sign)
        self.ui.backButton.clicked.connect(lambda: self.parent().replace_with(LogInWindow()))

    def __execute_sign(self):
        try:
            name = self.ui.line_name.text()
            surname = self.ui.line_surname.text()
            passport = self.ui.line_passport.text()
            login = self.ui.line_login.text()
            password = self.ui.line_password.text()

            ConnectionDB.cursor.execute(
                "INSERT INTO users (name, surname,passport_num,login,password) VALUES (%s,%s,%s,%s,%s)",
                (name, surname, passport, login, password))
            ConnectionDB.connect.commit()

            # creat instance of user in current session
            ConnectionDB.cursor.execute("SELECT user_id from users WHERE passport_num=%s", (passport,))
            user_id = ConnectionDB.cursor.fetchone()
            user = (user_id[0], name, surname, login, "user", passport, None, password)
            Current_User.set(user)
            # end of creating

            self.parent().replace_with(ProfileWindow())

        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

    def keyPressEvent(self, event):
        if self.ui.line_name.text() == "":
            return
        if self.ui.line_surname.text() == "":
            return
        if self.ui.line_passport.text() == "":
            return
        if self.ui.line_login.text() == "":
            return
        if self.ui.line_password.text() == "":
            return
        if event.key() == Qt.Key_Return:
            self.__execute_sign()

    def __del__(self):
        self.ui = None


class MainWindow(QMainWindow):
    def __init__(self, parent=None):
        QMainWindow.__init__(self, parent)
        self.ui = Ui_MainWindow()
        self.ui.setupUi(self)

        # переходим на окно log in
        self.current_widget = LogInWindow()
        self.ui.main_layout.addWidget(self.current_widget)

    def replace_with(self, new_widget):
        self.ui.main_layout.replaceWidget(self.current_widget, new_widget)
        self.current_widget.setParent(None)
        self.current_widget = new_widget

    def __del__(self):
        self.ui = None


class ChangeInfoWindow(QChangeInfo):
    def __init__(self, parent=None):
        QChangeInfo.__init__(self, parent)
        self.ui = Ui_WindowChangeInfo()
        self.ui.setupUi(self)

        self.ui.nameLine.setText(Current_User.name)
        self.ui.surnameLine.setText(Current_User.surname)
        self.ui.passporLine.setText(Current_User.passport_num)
        self.ui.phoneLine.setText(Current_User.phone_number)
        self.ui.loginLine.setText(Current_User.login)
        self.ui.passwordLine.setText(Current_User.password)

        self.ui.buttonDone.clicked.connect(self.saveInfo)

    # saves new information about user, checks it for validity
    def saveInfo(self):
        newName = self.ui.nameLine.text()
        newSurname = self.ui.surnameLine.text()
        newPassport = self.ui.passporLine.text()
        newPhone = self.ui.phoneLine.text()
        newLogin = self.ui.loginLine.text()
        newPassword = self.ui.passwordLine.text()

        try:
            ConnectionDB.cursor.execute("""SELECT user_id FROM users WHERE passport_num = %s""", (newPassport,))
            duplicated_users = ConnectionDB.cursor.fetchall()
            if len(duplicated_users) == 2:
                ErrorMessage('Error', 'This user already exists')
                raise Exception("USER ALREADY EXISTS")

            ConnectionDB.cursor.execute("""SELECT user_id FROM users WHERE login = %s""", (newLogin,))
            duplicated_users = ConnectionDB.cursor.fetchall()
            if len(duplicated_users) == 2:
                ErrorMessage('Error', 'The user with this login already exists')
                raise Exception("USER WITH THIS LOGIN ALREADY EXISTS")

            ConnectionDB.cursor.execute(
                """UPDATE users SET name = %s, surname=%s, login=%s, password=%s, passport_num=%s, phone_number=%s WHERE user_id=%s""",
                (newName, newSurname, newLogin, newPassword, newPassport, newPhone, Current_User.user_id))

            ConnectionDB.connect.commit()
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)
        # Modify user in current session
        Current_User.set((Current_User.user_id, newName, newSurname, newLogin, "user", newPassport, newPhone,
                          newPassword))

        self.parent().replace_with(ProfileWindow())

    def keyPressEvent(self, event):
        if self.ui.nameLine.text() == "":
            return
        if self.ui.surnameLine.text() == "":
            return
        if self.ui.passporLine.text() == "":
            return
        if self.ui.passwordLine.text() == "":
            return
        if self.ui.loginLine.text() == "":
            return
        if event.key() == Qt.Key_Return:
            self.saveInfo()

    def __del__(self):
        self.ui = None


class TicketWindow(QTicket):
    def __init__(self, parent=None):
        QTicket.__init__(self, parent)
        self.ui = Ui_WindowTicket()
        self.ui.setupUi(self)

        # initialization
        ticket = None
        flightDirection = None
        airline = None
        tariff = None
        try:
            # getting info about ticket from db
            ConnectionDB.cursor.execute(
                """SELECT flight_id, tickets.plane_id, serial_number_in_plane, tariff_id FROM tickets LEFT JOIN seats USING (seat_id) WHERE ticket_id=%s""",
                (Current_Ticket.ticket_id,))
            ticket = ConnectionDB.cursor.fetchone()
            # здесь нужно добавить rowFactory в перспективе
            ConnectionDB.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id = %s""",
                                        (ticket[0],))
            flightDirection = ConnectionDB.cursor.fetchone()
            ConnectionDB.cursor.execute("""SELECT company FROM planes WHERE plane_id=%s""", (ticket[1],))
            airline = ConnectionDB.cursor.fetchone()
            ConnectionDB.cursor.execute("""SELECT price, large_luggage, food FROM tariff WHERE tariff_id = %s""",
                                        (ticket[3],))
            tariff = ConnectionDB.cursor.fetchone()
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

        # putting info into window
        outDeparture = self.ui.departure
        outDeparture.setText(flightDirection[0])

        outDestination = self.ui.destination
        outDestination.setText(flightDirection[1])

        outAirline = self.ui.airline
        outAirline.setText(airline[0])

        outSeat = self.ui.seat
        outSeat.setText(str(ticket[2]))

        outPrice = self.ui.price
        outPrice.setText(str(tariff[0]))

        outLuggage = self.ui.lagguge
        outLuggage.setText("Услуга куплена" if tariff[1] else "Услуга не куплена")

        outFood = self.ui.food
        outFood.setText("Услуга куплена" if tariff[2] else "Услуга не куплена")

        self.ui.pushButtonOk.clicked.connect(
            lambda: self.parent().replace_with(ProfileWindow())
        )

        self.ui.returnTicket.clicked.connect(self.returnTick)

    def returnTick(self):
        ConnectionDB.cursor.execute("""SELECT * FROM return_ticket(%s,%s)""",
                                    (Current_User.user_id, Current_Ticket.ticket_id))
        ConnectionDB.connect.commit()
        self.parent().replace_with(ProfileWindow())

    def __del__(self):
        self.ui = None


class BuyTicketWindow(QBuyTicket):
    def __init__(self, parent=None):
        QBuyTicket.__init__(self, parent)
        self.ui = Ui_WindowBuyTicket()
        self.ui.setupUi(self)

        self.luggage_flag = False
        self.food_flag = False
        self.time = ""
        self.time_is_selected = False

        # buttons
        self.ui.button_back.clicked.connect(lambda: self.parent().replace_with(ProfileWindow()))
        self.ui.button_search.clicked.connect(lambda: self.show_answers())
        self.ui.listWidget_seats.itemClicked.connect(self.set_seat)

        # digital clock
        # self.timer = QTimer()
        # self.timer.timeout.connect(self._update)
        # self.timer.start(1000)
        # date
        date = QDateTime.currentDateTime().toString()
        date = re.sub(r'..:.*', '', date)
        self.ui.date_label.setText(date)

        # init comboboxes
        ConnectionDB.cursor.execute("SELECT DISTINCT departure from flights")
        result = ConnectionDB.cursor.fetchall()
        for departure in result:
            self.ui.comboBox_departure.addItem(str(departure[0]))
        self.ui.comboBox_departure.setCurrentIndex(0)
        Ticket_tb.departure = result[0][0]
        self.ui.comboBox_departure.activated[str].connect(self.change_departure_vars)

        ConnectionDB.cursor.execute("SELECT DISTINCT destination from flights")
        result = ConnectionDB.cursor.fetchall()
        for destination in result:
            self.ui.comboBox_destination.addItem(str(destination[0]))
        self.ui.comboBox_destination.setCurrentIndex(0)
        Ticket_tb.destination = result[0][0]
        self.ui.comboBox_destination.activated[str].connect(self.change_destination_vars)

        # add options
        self.ui.checkBox_luggage.toggled.connect(self.set_flags)
        self.ui.checkBox_food.toggled.connect(self.set_flags)

        # list of seats id
        self.seats_id = []

        # calendar
        self.time_list = []
        self.ui.calendarWidget.clicked[QDate].connect(self.search_time)

        # list of time
        self.ui.listWidget_times.itemClicked.connect(self.set_flightId_by_time)

    def set_flags(self):
        self.luggage_flag = self.ui.checkBox_luggage.checkState()
        self.food_flag = self.ui.checkBox_food.checkState()

    def search_time(self, date_):
        Ticket_tb.set_date(date_)
        print((Ticket_tb.departure, Ticket_tb.destination, Ticket_tb.year, Ticket_tb.month,
               Ticket_tb.day))
        ConnectionDB.cursor.execute("""SELECT * from current_time_by_flightDate (%s,%s,%s,%s,%s)""",
                                    (Ticket_tb.departure, Ticket_tb.destination, Ticket_tb.year, Ticket_tb.month,
                                     Ticket_tb.day))

        # если ответ пустой -- ответная реакция
        result = ConnectionDB.cursor.fetchall()
        for time_info in result:
            print(time_info)
            # time_info[0] ---- flight_id
            self.time_list.append(time_info[0])
            self.ui.listWidget_times.addItem(str(int(time_info[1])) + ":" + str(int(time_info[2])))

    def set_flightId_by_time(self):
        Ticket_tb.flight_id = self.time_list[self.ui.listWidget_times.currentRow()]
        self.time_is_selected = True

    def show_answers(self):
        if not self.time_is_selected:
            ErrorMessage('Error', 'Select time, please')
        else:
            if Ticket_tb.departure == Ticket_tb.destination:
                ErrorMessage('Error', 'Departure and destination should be different')
            else:
                self.seats_id.clear()
                ConnectionDB.cursor.execute(
                    """SELECT * from list_of_free_seats(SELECT plane_id FROM planes WHERE flight_id = %s)""",
                    (Ticket_tb.flight_id,))
                for seats in ConnectionDB.cursor.fetchall():
                    self.seats_id.append(seats[0])
                    self.ui.listWidget_seats.addItem(seats[1])

    def set_seat(self):
        Ticket_tb.seat_id = self.seats_id[self.ui.listWidget_seats.currentRow()]
        # elif self.time_is_selected == 1:

        # self.cursor.execute(
        #    """SELECT flight_id, flight_date from flights
        #       WHERE departure=%s and destination=%s and flight_date=%s""", (Ticket_tb.departure, Ticket_tb.destination, Ticket_tb.date))
        # result = self.cursor.fetchall()
        # if len(result) == 0:
        #    ErrorMessage("Warning", "No tickets")
        # for flight_info_ in result:
        #    date = str(flight_info_[1])
        # date = re.sub(r'.* ', '', str(flight_info_[1]))
        # date = re.sub(r'\..*', '', date)
        #     self.ui.listWidget_times.addItem(date)
        #            self.cursor.execute(
        #                """SELECT * from planes
        #                   WHERE flight_id = %s""", (flight_info_[0][0],))
        #            for flight_info in self.cursor.fetchall():
        #                Ticket_tb.plane_id = flight_info[0]
        #                Ticket_tb.seats_num = flight_info[1]
        #                Ticket_tb.company = flight_info[2]

        # self.cursor.execute(
        #    """select tariff_id, price from tariff
        #        where large_luggage=%s and food=%s""", (Ticket_tb.luggage, Ticket_tb.food))
        # for tariff_info in self.cursor.fetchall():
        #    Ticket_tb.tariff_id = tariff_info[0]
        #    Ticket_tb.price = tariff_info[1]

    def _update(self):
        time = QTime.currentTime().toString()
        time = time[0:-3]
        self.ui.lcdNumber.display(time)

    def change_departure_vars(self, text):
        Ticket_tb.set_departure(text)

    def change_destination_vars(self, text):
        Ticket_tb.set_destination(text)


class AdminWindow(QAdmin):
    def __init__(self, parent=None):
        QAdmin.__init__(self, parent)

        self.ui = Ui_Admin()
        self.ui.setupUi(self)

        self.user_field_fill()
        self.flight_field_fill()

        # self.ui.user_field.itemDoubleClicked.connect(self.user_profile)
        self.ui.flight_field.itemClicked.connect(self.flight_show_in_lineEdit)
        self.ui.addButton.clicked.connect(self.addFlightButton)
        self.ui.delButton.clicked.connect(self.delButton)
        self.ui.buttonEdit.clicked.connect(self.flight_edit)
        self.ui.backButton.clicked.connect(lambda: self.parent().replace_with(LogInWindow()))
        self.ui.adminLogin.setText("You are: " + str(Current_User.login))

    def user_field_fill(self):
        try:
            ConnectionDB.cursor.execute("""SELECT name || ' ' || surname, user_id FROM users""")
            for user in ConnectionDB.cursor.fetchall():
                self.ui.userField.addItem(str(user[0]) + " (user id = " + str(user[1]) + ")")
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

    def flight_field_fill(self):
        self.flight_ids = []
        try:
            ConnectionDB.cursor.execute("""SELECT departure, destination, flight_id FROM flights""")
            for flight in ConnectionDB.cursor.fetchall():
                self.ui.flight_field.addItem(str(flight[0]) + " ---> " + str(flight[1]))
                self.flight_ids.append(flight[2])
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

    def delButton(self):
        try:
            cur_flight_id = self.flight_ids[self.ui.flight_field.currentRow()]
            ConnectionDB.cursor.execute("""SELECT * FROM delete_flight_by_id (%s, %s)""",
                                        (Current_User.user_id, self.flight_ids[self.ui.flight_field.currentRow()]))
            # DON'T FORGET COMMIT
            ConnectionDB.connect.commit()
            # DON'T FORGET COMMIT

            item = self.ui.flight_field.takeItem(self.ui.flight_field.currentRow())
            self.flight_ids.remove(cur_flight_id)
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)
        self.ui.line_depart.setText("")
        self.ui.line_dest.setText("")

    def addFlightButton(self):
        self.ui.buttonEdit.clicked.disconnect()

        self.ui.buttonEdit.setText("Add flight")
        self.ui.line_depart.setText("")
        self.ui.line_dest.setText("")

        self.ui.buttonEdit.clicked.connect(self.addingNewFlight)

    def addingNewFlight(self):
        if len(self.ui.line_depart.text()) == 0:
            return
        if len(self.ui.line_dest.text()) == 0:
            return
        dep = self.ui.line_depart.text()
        dest = self.ui.line_dest.text()
        date = QDateTime(self.ui.flightDateEdit.dateTime())
        date_in_seconds = date.toTime_t()
        new_flight_id = None
        try:
            # проблема : попадаем сюда дважды для одних и тех же данных
            ConnectionDB.cursor.execute(
                """SELECT * FROM new_flight(%s,%s,%s,(SELECT TIMESTAMP 'epoch' + %s * INTERVAL '1 second'))""",
                (Current_User.user_id, dep, dest, date_in_seconds))
            # DON'T FORGET COMMIT
            ConnectionDB.connect.commit()
            # DON'T FORGET COMMIT
            #  response return flight_id
            response = ConnectionDB.cursor.fetchone()
            new_flight_id = response[1]
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

        self.ui.line_depart.setText("")
        self.ui.line_dest.setText("")

        try:
            ConnectionDB.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id =%s """,
                                        (new_flight_id,))
            flight = ConnectionDB.cursor.fetchone()
            self.ui.flight_field.addItem(str(flight[0]) + " ---> " + str(flight[1]))
            self.flight_ids.append(new_flight_id)

        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

        self.ui.buttonEdit.clicked.disconnect()
        self.ui.buttonEdit.clicked.connect(self.flight_edit)

        self.ui.flight_field.itemClicked.connect(self.flight_show_in_lineEdit)
        self.ui.buttonEdit.setText("Edit")

    # def user_profile(self):
    #     selected_item = self.ui.user_field.currentItem()
    #     user_id = int(re.findall('\d+', selected_item.text())[0])
    #     try:
    #         self.cursor.execute(
    #             """SELECT user_id, name ,surname, login , status, passport_num,
    #               phone_number,password
    #               from users WHERE user_id=%s""", (user_id,))
    #         user = self.cursor.fetchone()
    #         Current_User.set(user)
    #     except Exception as e:
    #         self.connect.rollback()
    #         print(e)
    #     self.parent().replace_with(ProfileWindow())

    def flight_edit(self):
        self.ui.buttonEdit.setText("Edit")

        if len(self.ui.line_depart.text()) == 0:
            return
        if len(self.ui.line_dest.text()) == 0:
            return

        depart = self.ui.line_depart.text()
        dest = self.ui.line_dest.text()
        date = QDateTime(self.ui.flightDateEdit.dateTime())
        date_in_seconds = date.toTime_t()
        try:
            ConnectionDB.cursor.execute(
                """SELECT * FROM change_flight(%s,%s,(SELECT TIMESTAMP 'epoch' + %s * INTERVAL '1 second'+INTERVAL '3 hour'),%s,%s)""",
                (Current_User.user_id,
                 self.flight_ids[self.ui.flight_field.currentRow()],
                 date_in_seconds, depart, dest))
            # DON'T FORGET COMMIT
            ConnectionDB.connect.commit()
            # DON'T FORGET COMMIT
            ConnectionDB.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id = %s""",
                                        (self.flight_ids[self.ui.flight_field.currentRow()],))
            flight = ConnectionDB.cursor.fetchone()
            cur_item = self.ui.flight_field.currentItem()
            cur_item.setText(str(flight[0]) + " ---> " + str(flight[1]))
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)

    def flight_show_in_lineEdit(self):
        self.ui.buttonEdit.setText("Edit")
        self.ui.buttonEdit.clicked.disconnect()
        current_flight_date = None
        try:
            ConnectionDB.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id =%s""",
                                        (self.flight_ids[self.ui.flight_field.currentRow()],))
            current_flight = ConnectionDB.cursor.fetchone()
            self.ui.line_depart.setText(current_flight[0])
            self.ui.line_dest.setText(current_flight[1])

            ConnectionDB.cursor.execute("""SELECT * FROM current_flaight_date(%s)""",
                                        (self.flight_ids[self.ui.flight_field.currentRow()],))
            current_flight_date = ConnectionDB.cursor.fetchone()
        except Exception as e:
            ConnectionDB.connect.rollback()
            print(e)
        flightDateLine = QDateTime(current_flight_date[0],
                                   current_flight_date[1],
                                   current_flight_date[2],
                                   current_flight_date[3],
                                   current_flight_date[4])
        self.ui.flightDateEdit.setDateTime(flightDateLine)

        self.ui.buttonEdit.clicked.connect(self.flight_edit)

    def __del__(self):
        self.ui = None


class TicketToBuy():
    def __init__(self):
        self.flight_id = None
        self.ticket_id = None  # ?
        self.seat_id = None  # ?
        self.plane_id = None  # ?
        self.user_id = Current_User.user_id
        self.year, self.month, self.day = QDate.currentDate().getDate()
        self.departure = ""
        self.destination = ""
        self.seats_num = None
        self.company = ""

    def set_date(self, date_):
        self.year, self.month, self.day = date_.getDate()

    def set_departure(self, departure_):
        self.departure = departure_

    def set_destination(self, destination_):
        self.destination = destination_


class Ticket():
    def __init__(self):
        self.ticket_id = None

    def set(self, ticket=None):
        self.ticket_id = ticket


class ConnectionDatabase():
    def __init__(self):
        try:
            self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
            self.cursor = self.connect.cursor()
        except Exception as e:
            self.connect.rollback()
            print(e)

    def __del__(self):
        self.cursor.close()
        self.connect.close()


class User():
    def __init__(self):
        self.user_id = None
        self.name = ""
        self.surname = ""
        self.login = ""
        self.status = "user"
        self.passport_num = ""
        self.phone_number = ""
        self.password = ""

    def set(self, user=(None, "", "", "", "user", "", "", "")):
        self.user_id = user[0]
        self.name = user[1]
        self.surname = user[2]
        self.login = user[3]
        self.status = user[4]
        self.passport_num = user[5]
        self.phone_number = user[6]
        self.password = user[7]


def PrintException():
    exc_type, exc_obj, tb = sys.exc_info()
    f = tb.tb_frame
    lineno = tb.tb_lineno
    filename = f.f_code.co_filename
    linecache.checkcache(filename)
    line = linecache.getline(filename, lineno, f.f_globals)
    print('EXCEPTION IN (LINE {} "{}"): {}'.format(lineno, line.strip(), exc_obj))


if __name__ == '__main__':
    # пользователь в сессии
    global Current_User
    Current_User = User()
    global Current_Ticket
    Current_Ticket = Ticket()
    # database connection
    global ConnectionDB
    ConnectionDB = ConnectionDatabase()

    global Ticket_tb
    Ticket_tb = TicketToBuy()

    app = QApplication(sys.argv)
    # создаем окно
    w = MainWindow()
    w.setWindowTitle("Air ticket")
    w.show()

    # w = AdminWindow()
    # w.setWindowTitle("ajksnd")
    # w.show()

    # enter tha main loop
    sys.exit(app.exec_())
