
import os
import sys
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QMainWindow, QLabel, QCheckBox, QWidget, QVBoxLayout
from Exporters.VCVExporter.export_vcv import export_vcv 
from Exporters.SCExporter.export_sc import export_sc
from Exporters.PluginExporter.export_plugin import export_plugin 





# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'exporterRrUNNk.ui'
##
## Created by: Qt User Interface Compiler version 6.10.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (QCoreApplication, QDate, QDateTime, QLocale,
    QMetaObject, QObject, QPoint, QRect,
    QSize, QTime, QUrl, Qt)
from PySide6.QtGui import (QBrush, QColor, QConicalGradient, QCursor,
    QFont, QFontDatabase, QGradient, QIcon,
    QImage, QKeySequence, QLinearGradient, QPainter,
    QPalette, QPixmap, QRadialGradient, QTransform)
from PySide6.QtWidgets import (QApplication, QCheckBox, QDialog, QLabel,
    QLineEdit, QPushButton, QRadioButton, QSizePolicy,
    QStackedWidget, QVBoxLayout, QWidget)

class Ui_MMMAudioExporter(object):
    def setupUi(self, MMMAudioExporter):
        if not MMMAudioExporter.objectName():
            MMMAudioExporter.setObjectName(u"MMMAudioExporter")
        MMMAudioExporter.resize(712, 431)


        self.stackedWidget = QStackedWidget(MMMAudioExporter)
        self.stackedWidget.setObjectName(u"stackedWidget")
        self.stackedWidget.setGeometry(QRect(0, 10, 701, 411))
        self.names = QWidget()
        self.names.setObjectName(u"names")
        self.names_package = QLineEdit(self.names)
        self.names_package.setObjectName(u"names_package")
        self.names_package.setGeometry(QRect(140, 100, 381, 32))
        self.names_graph = QLineEdit(self.names)
        self.names_graph.setObjectName(u"names_graph")
        self.names_graph.setGeometry(QRect(140, 180, 381, 32))
        self.label_2 = QLabel(self.names)
        self.label_2.setObjectName(u"label_2")
        self.label_2.setGeometry(QRect(30, 100, 111, 21))
        self.label_3 = QLabel(self.names)
        self.label_3.setObjectName(u"label_3")
        self.label_3.setGeometry(QRect(30, 180, 101, 21))
        self.names_package_browse = QPushButton(self.names)
        self.names_package_browse.setObjectName(u"names_package_browse")
        self.names_package_browse.setGeometry(QRect(530, 100, 88, 34))
        self.names_graph_browse = QPushButton(self.names)
        self.names_graph_browse.setObjectName(u"names_graph_browse")
        self.names_graph_browse.setGeometry(QRect(530, 180, 88, 34))
        self.names_name = QLineEdit(self.names)
        self.names_name.setObjectName(u"names_name")
        self.names_name.setGeometry(QRect(310, 260, 301, 32))
        self.label_4 = QLabel(self.names)
        self.label_4.setObjectName(u"label_4")
        self.label_4.setGeometry(QRect(30, 260, 251, 31))
        self.names_next = QPushButton(self.names)
        self.names_next.setObjectName(u"names_next")
        self.names_next.setGeometry(QRect(590, 350, 88, 34))
        self.label_5 = QLabel(self.names)
        self.label_5.setObjectName(u"label_5")
        self.label_5.setGeometry(QRect(30, 40, 411, 18))
        self.stackedWidget.addWidget(self.names)
        self.build_options = QWidget()
        self.build_options.setObjectName(u"build_options")
        self.verticalLayoutWidget = QWidget(self.build_options)
        self.verticalLayoutWidget.setObjectName(u"verticalLayoutWidget")
        self.verticalLayoutWidget.setGeometry(QRect(30, 80, 171, 171))
        self.verticalLayout_2 = QVBoxLayout(self.verticalLayoutWidget)
        self.verticalLayout_2.setObjectName(u"verticalLayout_2")
        self.verticalLayout_2.setContentsMargins(0, 0, 0, 0)
        self.vst = QCheckBox(self.verticalLayoutWidget)
        self.vst.setObjectName(u"vst")

        self.verticalLayout_2.addWidget(self.vst)

        self.clap = QCheckBox(self.verticalLayoutWidget)
        self.clap.setObjectName(u"clap")

        self.verticalLayout_2.addWidget(self.clap)

        self.au = QCheckBox(self.verticalLayoutWidget)
        self.au.setObjectName(u"au")

        self.verticalLayout_2.addWidget(self.au)

        self.ugen = QCheckBox(self.verticalLayoutWidget)
        self.ugen.setObjectName(u"ugen")

        self.verticalLayout_2.addWidget(self.ugen)

        self.vcv = QCheckBox(self.verticalLayoutWidget)
        self.vcv.setObjectName(u"vcv")

        self.verticalLayout_2.addWidget(self.vcv)

        self.label = QLabel(self.build_options)
        self.label.setObjectName(u"label")
        self.label.setGeometry(QRect(30, 50, 171, 18))
        self.build_options_next = QPushButton(self.build_options)
        self.build_options_next.setObjectName(u"build_options_next")
        self.build_options_next.setGeometry(QRect(590, 350, 88, 34))
        self.verticalLayoutWidget_2 = QWidget(self.build_options)
        self.verticalLayoutWidget_2.setObjectName(u"verticalLayoutWidget_2")
        self.verticalLayoutWidget_2.setGeometry(QRect(230, 80, 160, 61))
        self.verticalLayout_3 = QVBoxLayout(self.verticalLayoutWidget_2)
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.build_yes = QRadioButton(self.verticalLayoutWidget_2)
        self.build_yes.setObjectName(u"build_yes")

        self.verticalLayout_3.addWidget(self.build_yes)

        self.build_no = QRadioButton(self.verticalLayoutWidget_2)
        self.build_no.setObjectName(u"build_no")

        self.verticalLayout_3.addWidget(self.build_no)

        self.label_6 = QLabel(self.build_options)
        self.label_6.setObjectName(u"label_6")
        self.label_6.setGeometry(QRect(230, 50, 431, 18))
        self.verticalLayoutWidget_3 = QWidget(self.build_options)
        self.verticalLayoutWidget_3.setObjectName(u"verticalLayoutWidget_3")
        self.verticalLayoutWidget_3.setGeometry(QRect(230, 190, 160, 61))
        self.verticalLayout_4 = QVBoxLayout(self.verticalLayoutWidget_3)
        self.verticalLayout_4.setObjectName(u"verticalLayout_4")
        self.verticalLayout_4.setContentsMargins(0, 0, 0, 0)
        self.install_yes = QRadioButton(self.verticalLayoutWidget_3)
        self.install_yes.setObjectName(u"install_yes")

        self.verticalLayout_4.addWidget(self.install_yes)

        self.install_no = QRadioButton(self.verticalLayoutWidget_3)
        self.install_no.setObjectName(u"install_no")

        self.verticalLayout_4.addWidget(self.install_no)

        self.label_7 = QLabel(self.build_options)
        self.label_7.setObjectName(u"label_7")
        self.label_7.setGeometry(QRect(230, 160, 431, 18))
        self.verticalLayoutWidget_4 = QWidget(self.build_options)
        self.verticalLayoutWidget_4.setObjectName(u"verticalLayoutWidget_4")
        self.verticalLayoutWidget_4.setGeometry(QRect(230, 300, 160, 61))
        self.verticalLayout_5 = QVBoxLayout(self.verticalLayoutWidget_4)
        self.verticalLayout_5.setObjectName(u"verticalLayout_5")
        self.verticalLayout_5.setContentsMargins(0, 0, 0, 0)
        self.instrument_yes = QRadioButton(self.verticalLayoutWidget_4)
        self.instrument_yes.setObjectName(u"instrument_yes")

        self.verticalLayout_5.addWidget(self.instrument_yes)

        self.instrument_no = QRadioButton(self.verticalLayoutWidget_4)
        self.instrument_no.setObjectName(u"instrument_no")

        self.verticalLayout_5.addWidget(self.instrument_no)

        self.label_10 = QLabel(self.build_options)
        self.label_10.setObjectName(u"label_10")
        self.label_10.setGeometry(QRect(230, 270, 431, 18))
        self.stackedWidget.addWidget(self.build_options)
        self.extras = QWidget()
        self.extras.setObjectName(u"extras")
        self.resource_line = QLineEdit(self.extras)
        self.resource_line.setObjectName(u"resource_line")
        self.resource_line.setGeometry(QRect(150, 110, 491, 32))
        self.gui_line = QLineEdit(self.extras)
        self.gui_line.setObjectName(u"gui_line")
        self.gui_line.setGeometry(QRect(150, 200, 481, 32))
        self.extras_next = QPushButton(self.extras)
        self.extras_next.setObjectName(u"extras_next")
        self.extras_next.setGeometry(QRect(590, 350, 88, 34))
        self.label_12 = QLabel(self.extras)
        self.label_12.setObjectName(u"label_12")
        self.label_12.setGeometry(QRect(30, 110, 121, 18))
        self.label_13 = QLabel(self.extras)
        self.label_13.setObjectName(u"label_13")
        self.label_13.setGeometry(QRect(30, 210, 111, 18))
        self.label_14 = QLabel(self.extras)
        self.label_14.setObjectName(u"label_14")
        self.label_14.setGeometry(QRect(30, 40, 341, 18))
        self.stackedWidget.addWidget(self.extras)
        self.vcv_options = QWidget()
        self.vcv_options.setObjectName(u"vcv_options")
        self.input_names = QLineEdit(self.vcv_options)
        self.input_names.setObjectName(u"input_names")
        self.input_names.setGeometry(QRect(120, 60, 491, 32))
        self.output_names = QLineEdit(self.vcv_options)
        self.output_names.setObjectName(u"output_names")
        self.output_names.setGeometry(QRect(130, 170, 481, 32))
        self.label_8 = QLabel(self.vcv_options)
        self.label_8.setObjectName(u"label_8")
        self.label_8.setGeometry(QRect(30, 60, 101, 18))
        self.label_9 = QLabel(self.vcv_options)
        self.label_9.setObjectName(u"label_9")
        self.label_9.setGeometry(QRect(30, 180, 101, 18))
        self.vcv_next = QPushButton(self.vcv_options)
        self.vcv_next.setObjectName(u"vcv_next")
        self.vcv_next.setGeometry(QRect(590, 350, 88, 34))
        self.stackedWidget.addWidget(self.vcv_options)
        self.build_page = QWidget()
        self.build_page.setObjectName(u"build_page")
        self.build_button = QPushButton(self.build_page)
        self.build_button.setObjectName(u"build_button")
        self.build_button.setGeometry(QRect(570, 350, 88, 34))
        self.label_15 = QLabel(self.build_page)
        self.label_15.setObjectName(u"label_15")
        self.label_15.setGeometry(QRect(90, 60, 491, 18))
        self.stackedWidget.addWidget(self.build_page)
        self.page = QWidget()
        self.page.setObjectName(u"page")
        self.label_11 = QLabel(self.page)
        self.label_11.setObjectName(u"label_11")
        self.label_11.setGeometry(QRect(60, 50, 461, 21))
        self.stackedWidget.addWidget(self.page)

        self.retranslateUi(MMMAudioExporter)
        self.build_options_next.pressed.connect(self.stackedWidget.update)

        self.stackedWidget.setCurrentIndex(0)

        ## Next buttons
        self.names_next.clicked.connect(lambda: self.stackedWidget.setCurrentIndex(1))
        self.build_options_next.clicked.connect(lambda: self.stackedWidget.setCurrentIndex(2))
        
        self.extras_next.clicked.connect(self.on_extras_clicked)

        self.vcv_next.clicked.connect(lambda: self.stackedWidget.setCurrentIndex(4))
        self.build_button.clicked.connect(self.build)

        ## Defaults
        self.build_yes.toggle()
        self.install_no.toggle()
        self.instrument_yes.toggle()

        QMetaObject.connectSlotsByName(MMMAudioExporter)
    # setupUi

    def build(self):
        
        gui = self.gui_line.text()
        resources = []
    
        
        if self.names_name.text() == "":
            self.names_name = None
        else:
            self.names_name = self.names_name.text()
        print(gui, resources, self.names_name
              )
        if self.resource_line.text() != "":
            resources = self.resource_line.text().split(",")

        print(resources)
        
        if self.vcv.isChecked():
      

            inputs = self.input_names.text().split(",")
            outputs = self.output_names.text().split(",")

            export_vcv(
                graph_name=self.names_graph.text(),
                package_name=self.names_package.text(),
                module_name=self.names_name,
                gui_file=gui,
                instrument=False,
                install=self.install_yes.isChecked(),
                in_labels=inputs,
                num_in=len(inputs),
                out_labels=outputs,
                build=self.build_yes.isChecked(),
                resources=resources
            )

        if self.ugen.isChecked():
   

            export_sc(
                graph_name=self.names_graph.text(),
                package_name=self.names_package.text(),
                ugen_name=self.names_name,
                gui_file=gui,
                instrument=self.instrument_yes.isChecked(),
                install=self.install_yes.isChecked(),
                config="Release",
                build=self.build_yes.isChecked(),
                resources=resources
            )

        if self.vst.isChecked() or self.clap.isChecked() or self.au.isChecked():
            plugin_formats = []
            if self.vst.isChecked():
                plugin_formats.append("VST3")
            if self.clap.isChecked():
                 plugin_formats.append("Clap")
            if self.au.isChecked():
                 plugin_formats.append("AU")
            
            export_plugin(
                graph_name=self.names_graph.text(),
                package_name=self.names_package.text(),
                plugin_name=self.names_name,
                gui_file=gui,
                instrument=self.instrument_yes.isChecked(),
                install=self.install_yes.isChecked(),
                plugin_type=plugin_formats,
                build=self.build_yes.isChecked(),
                resources=resources
            )
        self.stackedWidget.setCurrentIndex(5)
  
        
    def on_extras_clicked(self):
        if self.vcv.isChecked():
            self.stackedWidget.setCurrentIndex(3)
        else:
            self.stackedWidget.setCurrentIndex(4)
    
    def retranslateUi(self, MMMAudioExporter):
        MMMAudioExporter.setWindowTitle(QCoreApplication.translate("MMMAudioExporter", u"MMMAudio Graph Exporter", None))
        self.names_package.setText(QCoreApplication.translate("MMMAudioExporter", u"examples", None))
        self.names_graph.setText(QCoreApplication.translate("MMMAudioExporter", u"ManyOscillators", None))
        self.label_2.setText(QCoreApplication.translate("MMMAudioExporter", u"Package name", None))
        self.label_3.setText(QCoreApplication.translate("MMMAudioExporter", u"Graph name", None))
        self.names_package_browse.setText(QCoreApplication.translate("MMMAudioExporter", u"Browse...", None))
        self.names_graph_browse.setText(QCoreApplication.translate("MMMAudioExporter", u"Browse...", None))
        self.label_4.setText(QCoreApplication.translate("MMMAudioExporter", u"Name (defaults to graph name if blank)", None))
        self.names_next.setText(QCoreApplication.translate("MMMAudioExporter", u"Next", None))
        self.label_5.setText(QCoreApplication.translate("MMMAudioExporter", u"Select the MMMAudio graph you would like to export.", None))
        self.vst.setText(QCoreApplication.translate("MMMAudioExporter", u"VST3", None))
        self.clap.setText(QCoreApplication.translate("MMMAudioExporter", u"Clap", None))
        self.au.setText(QCoreApplication.translate("MMMAudioExporter", u"AU (Mac only)", None))
        self.ugen.setText(QCoreApplication.translate("MMMAudioExporter", u"SuperCollider UGEN", None))
        self.vcv.setText(QCoreApplication.translate("MMMAudioExporter", u"VCV Rack Module", None))
        self.label.setText(QCoreApplication.translate("MMMAudioExporter", u"Select desired exports", None))
        self.build_options_next.setText(QCoreApplication.translate("MMMAudioExporter", u"Next", None))
        self.build_yes.setText(QCoreApplication.translate("MMMAudioExporter", u"Yes", None))
        self.build_no.setText(QCoreApplication.translate("MMMAudioExporter", u"No", None))
        self.label_6.setText(QCoreApplication.translate("MMMAudioExporter", u"Build targets? (If no you will need to build them yourself with CMake)", None))
        self.install_yes.setText(QCoreApplication.translate("MMMAudioExporter", u"Yes", None))
        self.install_no.setText(QCoreApplication.translate("MMMAudioExporter", u"No", None))
        self.label_7.setText(QCoreApplication.translate("MMMAudioExporter", u"Install targets? (If yes targets will be instaled in default paths)", None))
        self.instrument_yes.setText(QCoreApplication.translate("MMMAudioExporter", u"Yes", None))
        self.instrument_no.setText(QCoreApplication.translate("MMMAudioExporter", u"No", None))
        self.label_10.setText(QCoreApplication.translate("MMMAudioExporter", u"Export as instrument (No inputs)", None))
        self.resource_line.setText("")
        self.gui_line.setText("")
        self.extras_next.setText(QCoreApplication.translate("MMMAudioExporter", u"Next", None))
        self.label_12.setText(QCoreApplication.translate("MMMAudioExporter", u"Paths to Resources", None))
        self.label_13.setText(QCoreApplication.translate("MMMAudioExporter", u"Path to GUI File", None))
        self.label_14.setText(QCoreApplication.translate("MMMAudioExporter", u"Optional additional files", None))
        self.input_names.setText(QCoreApplication.translate("MMMAudioExporter", u"L, R", None))
        self.output_names.setText(QCoreApplication.translate("MMMAudioExporter", u"L, R", None))
        self.label_8.setText(QCoreApplication.translate("MMMAudioExporter", u"Input Labels", None))
        self.label_9.setText(QCoreApplication.translate("MMMAudioExporter", u"Output Labels", None))
        self.vcv_next.setText(QCoreApplication.translate("MMMAudioExporter", u"Next", None))
        self.build_button.setText(QCoreApplication.translate("MMMAudioExporter", u"Build", None))
        self.label_15.setText(QCoreApplication.translate("MMMAudioExporter", u"Press build to start, this may take some time.", None))
        self.label_11.setText(QCoreApplication.translate("MMMAudioExporter", u"All targets successfully exported, you may now close the window.", None))
# retranslateUi


class MainWindow(QMainWindow):
     def __init__(self):
          super().__init__()
          self.ui = Ui_MMMAudioExporter()
          self.ui.setupUi(self)


def main():
     app = QApplication(sys.argv)
     window = MainWindow()
     window.show()
     sys.exit(app.exec())



if __name__ == "__main__":
    main()
