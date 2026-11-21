"""
Shows how to load an audio buffer from a sound file and play it using the Play UGen, with Interp.sinc16 interpolation and a playback speed of -200 to 200.

A small window controls Play's playback speed and the VAMoogLadder filter's cutoff frequency:

  * rate: -200 to 200, with 0 in the centre (left of centre plays backwards). The slider
    is curved the same way on both sides so the normal speeds stay usable: 1x is a little
    right of centre, 25x three quarters of the way, and 200x at the right edge.
    The "1x" and "0" buttons jump straight to normal speed and to a stop.
  * cutoff: the filter's cutoff, from 100 Hz to 20 kHz.

This example is able to run by pressing the "play" button in VSCode or compiling and running the whole file on the command line.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *
from mmm_python.GUI import Handle, ControlSpec, BipolarSpec
from PySide6.QtWidgets import QApplication, QHBoxLayout, QPushButton, QVBoxLayout, QWidget


def main():
    mmm_audio = MMMAudio(128, graph_name="PlayExample_Sinc16", package_name="examples")
    mmm_audio.start_audio() # start the audio thread - or restart it where it left off

    app = QApplication([])

    window = QWidget()
    window.setWindowTitle("Play (sinc16)")
    window.resize(480, 160)
    # stop audio when the window is closed
    window.closeEvent = lambda event: (mmm_audio.exit_all(), event.accept())

    layout = QVBoxLayout()

    # these defaults match the ones in PlayExample_Sinc16.mojo
    rate = Handle(
        "rate",
        BipolarSpec(200.0, 4.0),
        1.0,
        callback=lambda v: mmm_audio.send_float("play_rate", v),
        resolution=10000,
        display_resolution=3,
    )
    layout.addWidget(rate)

    cutoff = Handle(
        "cutoff",
        ControlSpec(100.0, 20000.0, 2.0),
        20000.0,
        callback=lambda v: mmm_audio.send_float("lpf_freq", v),
        resolution=10000,
        display_resolution=0,
    )
    layout.addWidget(cutoff)

    layout.addStretch()
    window.setLayout(layout)

    mmm_audio.send_float("play_rate", 1.0)
    mmm_audio.send_float("lpf_freq", 20000.0)

    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
