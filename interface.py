#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# goi to
# work with windows
import sys

from PyQt5.QtCore import Qt
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
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')

        self.ui = Ui_WindowLogin()
        self.ui.setupUi(self)

        self.ui.sign_up_button.clicked.connect(
            lambda: self.parent().replace_with(RegistrationWindow())
        )
        self.ui.sign_in_button.clicked.connect(self.__execute_login)

    def __del__(self):
        self.cursor.close()
        self.connect.close()
        self.ui = None

    def __execute_login(self):
        try:
            self.cursor = self.connect.cursor()
            login = self.ui.line_login.text()
            password = self.ui.line_password.text()

            self.cursor.execute(
                """SELECT user_id, name ,surname, login , status, passport_num, 
                  phone_number,password 
                  from users WHERE login=%s AND password=%s""",
                (login, password))
            user = self.cursor.fetchone()
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

        except Exception as e:
            self.connect.rollback()
            print(e)

    # обработка нажатия на "enter"
    def keyPressEvent(self, event):
        if self.ui.line_login.text()=="":
            return
        if self.ui.line_password.text()!="":
            return
        if event.key() == Qt.Key_Return:
            self.__execute_login()


class ProfileWindow(QProfile):
    def __init__(self, parent=None):
        QProfile.__init__(self, parent)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
        self.cursor = self.connect.cursor()

        self.ui = Ui_Profile()
        self.ui.setupUi(self)

        # self.ui.button_buy.clicked.connect(lambda: self.parent().replace_with(BuyTicketWindow()))
        self.ui.button_change.clicked.connect(lambda: self.parent().replace_with(ChangeInfoWindow()))

        # display user info
        self.ui.label_name.setText(Current_User.name if Current_User.name != "" else "[No data]")
        self.ui.label_surname.setText(Current_User.surname if Current_User.name != "" else "[No data]")
        self.ui.label_login.setText(Current_User.login if Current_User.login != "" else "[No data]")
        self.ui.label_password.setText(Current_User.password if Current_User.password != "" else "[No data]")
        self.ui.label_passport.setText(Current_User.passport_num if Current_User.passport_num != "" else "[No data]")
        self.ui.label_phone.setText(Current_User.phone_number if Current_User.phone_number != "" else "[No data]")

        # combobox: watch a list of bought tickets
        self.cursor.execute("SELECT ticket_id from tickets WHERE user_id=%s", (Current_User.user_id,))
        result = self.cursor.fetchall()
        for ticket in result:
            self.ui.comboBox_tickets.addItem(str(ticket))

        self.ui.comboBox_tickets.activated[str].connect(self.do_sth)

    def do_sth(self, text):
        Current_Ticket.set(int(text[1:-2]))
        print(int(text[1:-2]))
        self.parent().replace_with(TicketWindow())

    def __del__(self):
        self.cursor.close()
        self.connect.close()
        self.ui = None


class RegistrationWindow(QRegistration):
    def __init__(self, parent=None):
        QRegistration.__init__(self, parent)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')

        self.ui = Ui_WindowRegistration()
        self.ui.setupUi(self)

        self.ui.sign_up_button.clicked.connect(self.__execute_sign)

    def __execute_sign(self):
        try:
            self.cursor = self.connect.cursor()
            name = self.ui.line_name.text()
            surname = self.ui.line_surname.text()
            passport = self.ui.line_passport.text()
            login = self.ui.line_login.text()
            password = self.ui.line_password.text()

            self.cursor.execute(
                "INSERT INTO users (name, surname,passport_num,login,password) VALUES (%s,%s,%s,%s,%s)",
                (name, surname, passport, login, password))
            self.connect.commit()

            # creat instance of user in current session
            self.cursor.execute("SELECT user_id from users WHERE passport_num=%s", (passport,))
            user_id = self.cursor.fetchone()
            user = (user_id[0], name, surname, login, "user", passport, None, password)
            Current_User.set(user)
            # end of creating

            self.parent().replace_with(ProfileWindow())

        except Exception as e:
            self.connect.rollback()
            print(e)

    def __del__(self):
        self.cursor.close()
        self.connect.close()
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
            self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
            self.cursor = self.connect.cursor()
            self.cursor.execute("""SELECT user_id FROM users WHERE passport_num = %s""", (newPassport,))
            duplicated_users = self.cursor.fetchall()
            if len(duplicated_users)==2:
                ErrorMessage('Error', 'This user already exists')
                raise Exception("USER ALREADY EXISTS")

            self.cursor.execute("""SELECT user_id FROM users WHERE login = %s""", (newLogin,))
            duplicated_users = self.cursor.fetchall()
            if len(duplicated_users)==2:
                ErrorMessage('Error', 'The user with this login already exists')
                raise Exception("USER WITH THIS LOGIN ALREADY EXISTS")

            self.cursor.execute(
                """UPDATE users SET name = %s, surname=%s, login=%s, password=%s, passport_num=%s, phone_number=%s WHERE user_id=%s""",
                (newName, newSurname, newLogin, newPassword, newPassport, newPhone,Current_User.user_id))

            self.connect.commit()
        except Exception as e:
            self.connect.rollback()
            print(e)
        # Modify user in current session
        Current_User.set((Current_User.user_id, newName, newSurname, newLogin, "user", newPassport, newPhone,
                          newPassword))

        self.parent().replace_with(ProfileWindow())

    def __del__(self):
        self.cursor.close()
        self.connect.close()
        self.ui = None


class TicketWindow(QTicket):
    def __init__(self, parent=None):
        QTicket.__init__(self, parent)
        self.ui = Ui_WindowTicket()
        self.ui.setupUi(self)
        try:
            self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
            self.cursor = self.connect.cursor()

            # getting info about ticket from db
            self.cursor.execute("""SELECT flight_id, plane_id, seat_id, tariff_id FROM tickets WHERE ticket_id=%s""",
                                (Current_Ticket.ticket_id,))
            ticket = self.cursor.fetchone()
            # здесь нужно добавить rowFactory в перспективе
            self.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id = %s""", (ticket[0],))
            flightDirection = self.cursor.fetchone()
            self.cursor.execute("""SELECT company FROM planes WHERE plane_id=%s""", (ticket[1],))
            airline = self.cursor.fetchone()
            self.cursor.execute("""SELECT price, large_luggage FROM tariff WHERE tariff_id = %s""", (ticket[3],))
            tariff = self.cursor.fetchone()
        except Exception as e:
            self.connect.rollback()
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

        self.ui.pushButtonOk.clicked.connect(
            lambda: self.parent().replace_with(ProfileWindow())
        )

        self.ui.returnTicket.clicked.connect(self.returnTick)

    def returnTick(self):
        self.cursor.execute("""DELETE FROM tickets WHERE ticket_id = %s""", (Current_Ticket.ticket_id,))
        self.connect.commit()
        self.parent().replace_with(ProfileWindow())

    def __del__(self):
        self.cursor.close()
        self.connect.close()
        self.ui = None


class AdminWindow(QAdmin):
    def __init__(self, parent=None):
        QAdmin.__init__(self, parent)

        self.ui = Ui_Admin()
        self.ui.setupUi(self)

        try:
            self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
            self.cursor = self.connect.cursor()
        except Exception as e:
            self.connect.rollback()
            print(e)

        self.user_field_fill()
        self.flight_field_fill()

        # self.ui.user_field.itemDoubleClicked.connect(self.user_profile)
        self.ui.flight_field.itemClicked.connect(self.flight_edit)
        self.ui.backButton.clicked.connect(lambda: self.parent().replace_with(LogInWindow()))
        self.ui.adminLogin.setText("You are: "+str(Current_User.login))

    def user_field_fill(self):
        try:
            self.cursor.execute("""SELECT name || ' ' || surname, user_id FROM users""")
            for user in self.cursor.fetchall():
                self.ui.user_field.addItem(str(user[0]) + " (user id = " + str(user[1]) + ")")
        except Exception as e:
            self.connect.rollback()
            print(e)

    def flight_field_fill(self):
        try:
            self.cursor.execute("""SELECT departure, destination, flight_id FROM flights""")
            for flight in self.cursor.fetchall():
                self.ui.flight_field.addItem(
                    "departure - destination: " + str(flight[0]) + " ---> " + str(flight[1]) + " (flight_id = " + str(
                        flight[2]) + ")")
        except Exception as e:
            self.connect.rollback()
            print(e)

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
        selected_item = self.ui.flight_field.currentItem()
        flight_id = int(re.findall('\d+', selected_item.text())[0])
        try:
            self.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id =%s""",(flight_id,))
            current_flight = self.cursor.fetchone()
            self.ui.line_depart.setText(current_flight[0])
            self.ui.line_dest.setText(current_flight[1])
            # self.ui.backButton.clicked.disconnect()
        except Exception as e:
            self.connect.rollback()
            print(e)

class Ticket():
    def __init__(self):
        self.ticket_id = None

    def set(self, ticket=None):
        self.ticket_id = ticket


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


if __name__ == '__main__':
    # пользователь в сессии
    global Current_User
    Current_User = User()
    global Current_Ticket
    Current_Ticket = Ticket()

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
