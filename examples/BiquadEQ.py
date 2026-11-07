"""
5-band parametric EQ using Biquad filters.
Demonstrates: lowshelf, 3x bell (peaking EQ), highshelf
"""

import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_python package.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python.MMMAudio import MMMAudio
from mmm_python.GUI import Handle, ControlSpec
from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QLabel


def main():
    mmm_audio = MMMAudio(128, graph_name="BiquadEQ", package_name="examples")
    mmm_audio.start_audio()

    app = QApplication([])
    window = QWidget()
    window.setWindowTitle("5-Band Biquad EQ")
    window.resize(400, 500)
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    layout = QVBoxLayout()

    # Low Shelf
    layout.addWidget(QLabel("<b>Low Shelf</b>"))
    ls_freq = Handle("LS Freq", ControlSpec(50, 200, 0.5), 100,
                     callback=lambda v: mmm_audio.send_float("ls_freq", v), run_callback_on_init=True)
    ls_gain = Handle("LS Gain (dB)", ControlSpec(-12, 12), 0,
                     callback=lambda v: mmm_audio.send_float("ls_gain", v), run_callback_on_init=True)
    layout.addWidget(ls_freq)
    layout.addWidget(ls_gain)

    # Bell 1
    layout.addWidget(QLabel("<b>Bell 1</b>"))
    b1_freq = Handle("B1 Freq", ControlSpec(200, 500, 0.5), 250,
                     callback=lambda v: mmm_audio.send_float("b1_freq", v), run_callback_on_init=True)
    b1_gain = Handle("B1 Gain (dB)", ControlSpec(-12, 12), 0,
                     callback=lambda v: mmm_audio.send_float("b1_gain", v), run_callback_on_init=True)
    b1_q = Handle("B1 Q", ControlSpec(0.5, 5), 1.0,
                  callback=lambda v: mmm_audio.send_float("b1_q", v), run_callback_on_init=True)
    layout.addWidget(b1_freq)
    layout.addWidget(b1_gain)
    layout.addWidget(b1_q)

    # Bell 2
    layout.addWidget(QLabel("<b>Bell 2</b>"))
    b2_freq = Handle("B2 Freq", ControlSpec(500, 2000, 0.5), 1000,
                     callback=lambda v: mmm_audio.send_float("b2_freq", v), run_callback_on_init=True)
    b2_gain = Handle("B2 Gain (dB)", ControlSpec(-12, 12), 0,
                     callback=lambda v: mmm_audio.send_float("b2_gain", v), run_callback_on_init=True)
    b2_q = Handle("B2 Q", ControlSpec(0.5, 5), 1.0,
                  callback=lambda v: mmm_audio.send_float("b2_q", v), run_callback_on_init=True)
    layout.addWidget(b2_freq)
    layout.addWidget(b2_gain)
    layout.addWidget(b2_q)

    # Bell 3
    layout.addWidget(QLabel("<b>Bell 3</b>"))
    b3_freq = Handle("B3 Freq", ControlSpec(2000, 8000, 0.5), 4000,
                     callback=lambda v: mmm_audio.send_float("b3_freq", v), run_callback_on_init=True)
    b3_gain = Handle("B3 Gain (dB)", ControlSpec(-12, 12), 0,
                     callback=lambda v: mmm_audio.send_float("b3_gain", v), run_callback_on_init=True)
    b3_q = Handle("B3 Q", ControlSpec(0.5, 5), 1.0,
                  callback=lambda v: mmm_audio.send_float("b3_q", v), run_callback_on_init=True)
    layout.addWidget(b3_freq)
    layout.addWidget(b3_gain)
    layout.addWidget(b3_q)

    # High Shelf
    layout.addWidget(QLabel("<b>High Shelf</b>"))
    hs_freq = Handle("HS Freq", ControlSpec(5000, 12000, 0.5), 8000,
                     callback=lambda v: mmm_audio.send_float("hs_freq", v), run_callback_on_init=True)
    hs_gain = Handle("HS Gain (dB)", ControlSpec(-12, 12), 0,
                     callback=lambda v: mmm_audio.send_float("hs_gain", v), run_callback_on_init=True)
    layout.addWidget(hs_freq)
    layout.addWidget(hs_gain)

    window.setLayout(layout)
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()