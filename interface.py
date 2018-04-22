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
Ui_WindowTicket,QTicket=uic.loadUiType('ticket.ui')



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

            self.cursor.execute("SELECT user_id from users WHERE login=%s AND password=%s",
                                (login, password))
            user_id = self.cursor.fetchone()
            if not user_id:
                self.showMessageBox('Warning', 'Invalid Username And Password')
                raise Exception("USER NOT EXISTS")

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


class TicketWindow(QTicket):
    def __init__(self, parent=None):
        QTicket.__init__(self, parent)
        self.ui = Ui_WindowTicket()
        self.ui.setupUi(self)
        self.connect = psycopg2.connect(database='db_project', user='kirill', host='localhost', password='25112458')
        self.cursor = self.connect.cursor()

        # здесь нужно добавить вывод инфы о билетах
        # self.cursor.execute("")
        ticketTable=self.ui.label
        ticketTable.setText("kamlsdm")

    def __del__(self):
        self.ui = None


class User():
    def __init__(self):
        self.user_id=0
        self.name=""
        self.surname=""
        self.login=""
        self.status="user"
        self.passport_num=""
        self.phone_number=""
        self.password=""

    def set(self,id=0,name="",surnam="",login="",status="",passport="", phone_number="",password=""):
        self.user_id = id
        self.name = name
        self.surname = surnam
        self.login = login
        self.status = status
        self.passport_num = passport
        self.phone_number = phone_number
        self.password = password


if __name__ == '__main__':

    # пользователь в сессии
    global User

    app = QApplication(sys.argv)
    # создаем окно
    w = MainWindow()
    w.setWindowTitle("Main window")
    w.show()

    # w=TicketWindow()
    # w.setWindowTitle("ajksnd")
    # w.show()

    # enter tha main loop
    sys.exit(app.exec_())
