"""
Van der Pol oscillator demo using RK4.

mu controls nonlinearity: 0 = sine wave, higher values = increasingly
distorted limit cycle waveform. gain controls output amplitude.
"""
import sys
from pathlib import Path

# Skip this line if running from REPL
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="VanDerPol", package_name="examples")
mmm_audio.start_audio()

app = QApplication([])

def run_gui():
    window = QWidget()
    window.setWindowTitle("VanDerPol")
    window.resize(300, 150)

    layout = QVBoxLayout()
    layout.setSpacing(0)

    def add_handle(name: str, min: float, max: float, exp: float, default: float):
        slider = Handle(name, ControlSpec(min, max, exp), default, callback=lambda v: mmm_audio.send_float(name, v))
        layout.addWidget(slider)
        mmm_audio.send_float(name, default)

    add_handle("frequency", 20.0, 2000.0, 0.25, 440.0)  # oscillator frequency
    add_handle("mu",        0.0,  5.0,    1.0,  1.0)    # nonlinearity: 0 = sine, 5 = distorted
    add_handle("gain",      0.0,  1.0,    1.0,  0.5)    # output amplitude

    window.setLayout(layout)
    window.show()
    window.raise_()
    app.exec()

run_gui()
mmm_audio.stop_audio()