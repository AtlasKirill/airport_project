#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# work with windows
import sys

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import QApplication, QMessageBox, QTableWidget, QTableWidgetItem
from PyQt5 import uic
import psycopg2

Ui_WindowLogin, QLogIn = uic.loadUiType('login.ui')
Ui_MainWindow, QMainWindow = uic.loadUiType('mainwindow.ui')
Ui_WindowRegistration, QRegistration = uic.loadUiType('registration.ui')
Ui_WindowTicket, QTicket = uic.loadUiType('ticket.ui')
Ui_WindowChangeInfo, QChangeInfo = uic.loadUiType('changeinfo.ui')


class LogInWindow(QLogIn):
    def __init__(self, parent=None):

        QLogIn.__init__(self, parent)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')

        self.ui = Ui_WindowLogin()
        self.ui.setupUi(self)
        # query_Text - здесь название поля из названия элементов в qtcreator
        self.ui.line_login.setText("email, например")
        self.ui.line_password.setText("Ваш пароль")

        self.ui.sign_up_button.clicked.connect(
            lambda: self.parent().replace_with(RegistrationWindow())
        )
        self.ui.sign_in_button.clicked.connect(self.__execute_login)

    def __del__(self):
        self.cursor.close()
        self.connect.close()
        self.ui = None

    def showMessageBox(self, title, message):
        msgBox = QMessageBox()
        msgBox.setIcon(QMessageBox.Warning)
        msgBox.setWindowTitle(title)
        msgBox.setText(message)
        msgBox.setStandardButtons(QMessageBox.Ok)
        msgBox.exec_()

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
                self.showMessageBox('Warning', 'Invalid Username And Password')
                raise Exception("USER NOT EXISTS")

            # creat instance of user in current session
            Current_User.set(user)


            # переход в новое окно


        except Exception as e:
            self.connect.rollback()
            print(e)

    # обработка нажатия на "enter"
    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Return and self.ui.line_login.hasFocus() \
                and self.ui.line_password.hasFocus():
            self.__execute_login()


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
            user = (user_id, name, surname, login, "user", passport, None, password)
            Current_User.set(user)
            # end of creating

        # переход в новое окно
        except Exception as e:
            self.connect.rollback()
            print(e)


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
    def __init__(self,parent=None):
        QChangeInfo.__init__(self,parent)
        self.ui= Ui_WindowChangeInfo()
        self.ui.setupUi(self)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
        self.cursor = self.connect.cursor()

        self.ui.nameLine.setText(Current_User.name)
        self.ui.surnameLine.setText(Current_User.surname)
        self.ui.passporLine.setText(Current_User.passport_num)
        self.ui.phoneLine.setText(Current_User.phone_number)
        self.ui.loginLine.setText(Current_User.login)
        self.ui.passwordLine.setText(Current_User.password)

        self.ui.buttonDone.clicked.connect()

    # saves new information about user, checks it for validity
    def saveInfo(self):
        newName = self.ui.nameLine.text()



class TicketWindow(QTicket):
    def __init__(self, parent=None, ticket_id=1):
        # ticket_id needs for display appropriate ticket
        self.ticket_id = ticket_id

        QTicket.__init__(self, parent)
        self.ui = Ui_WindowTicket()
        self.ui.setupUi(self)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
        self.cursor = self.connect.cursor()

        # getting info about ticket from db
        self.cursor.execute("""SELECT flight_id, plane_id, seat_id, tariff_id FROM tickets WHERE ticket_id=%s""",
                            (self.ticket_id,))
        ticket = self.cursor.fetchone()
        # здесь нужно добавить rowFactory в перспективе
        self.cursor.execute("""SELECT departure, destination FROM flights WHERE flight_id = %s""", (ticket[0],))
        flightDirection = self.cursor.fetchone()
        self.cursor.execute("""SELECT company FROM planes WHERE plane_id=%s""", (ticket[1],))
        airline = self.cursor.fetchone()
        self.cursor.execute("""SELECT price, large_luggage FROM tariff WHERE tariff_id = %s""", (ticket[3],))
        tariff = self.cursor.fetchone()

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

        # self.ui.pushButtonOk.clicked.connect(
        #     lambda: self.parent().replace_with(ProfileWindow())
        # )

    def __del__(self):
        self.ui = None


class User():
    def __init__(self):
        self.user_id = 0
        self.name = ""
        self.surname = ""
        self.login = ""
        self.status = "user"
        self.passport_num = ""
        self.phone_number = ""
        self.password = ""

    def set(self, user=(0, "", "", "", "user", "", "", "")):
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

    app = QApplication(sys.argv)
    # создаем окно
    # w = MainWindow()
    # w.setWindowTitle("Main window")
    # w.show()

    w = TicketWindow()
    w.setWindowTitle("ajksnd")
    w.show()

    # enter tha main loop
    sys.exit(app.exec_())
