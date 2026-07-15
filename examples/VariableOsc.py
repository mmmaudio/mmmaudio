"""
this example shows how to use the variable wavetable oscillator. 
it shows how the oscillator can be made using linear, quadratic, or sinc interpolation and can also be set to use oversampling. with sinc interpolation, use TimesOversampling.none or TimesOversampling.x2. with linear or quadratic interpolation, use an any oversampling up to TimesOversampling.x16.
"""

import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python import *
def main():
    # instantiate and load the graph
    mmm_audio = MMMAudio(128, graph_name="VariableOsc", package_name="examples")
    mmm_audio.start_audio() 

    from mmm_python.GUI import Slider2D
    from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QCheckBox

    app = QApplication([])
    app.quitOnLastWindowClosed = True 

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Variable Oscillator Controller")
    window.resize(300, 300)
    # stop audio when window is closed
    window.closeEvent = lambda event: (mmm_audio.stop_audio(), event.accept())

    # Create layout
    layout = QVBoxLayout()

    slider2d = Slider2D(250, 250)

    def on_slider_change(x, y):
        mmm_audio.send_float("x", x)  # map x from 0-1 to 20-2020 Hz
        mmm_audio.send_float("y", y)  # map y from 0-1 to 0-1 amplitude
    def slider_pressed(is_down):
        mmm_audio.send_bool("mouse_down", is_down)  # set amplitude to 0 when mouse is released

    slider2d.valueChanged.connect(on_slider_change)
    slider2d.pressed.connect(slider_pressed)
    layout.addWidget(slider2d)
    window.setLayout(layout)
    window.show()
    app.exec()

if __name__ == "__main__":
    main()