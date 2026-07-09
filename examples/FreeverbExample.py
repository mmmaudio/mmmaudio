"""
A classic reverb effect using the Freeverb UGen.

This example demonstrates how to use the Freeverb graph in MMM-Audio and how to control its parameters via a simple GUI built with PySide6.
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

from mmm_python import *
from PySide6.QtWidgets import *

def main():
    mmm_audio = MMMAudio(128, graph_name="FreeverbExample", package_name="examples")

    mmm_audio.start_audio() # start the audio thread - or restart it where it left off

    app = QApplication([])

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Freeverb Controller")
    window.resize(300, 100)
    # stop audio when window is closed
    window.closeEvent = lambda event: (mmm_audio.stop_audio(), event.accept())

    # Create layout
    layout = QVBoxLayout()

    # Create a slider
    roomsize_slider = Handle("room size", ControlSpec(0, 1.0, 0.25), 0.5, callback=lambda v: mmm_audio.send_float("room_size", v), run_callback_on_init=True)
    layout.addWidget(roomsize_slider)

    lpf = Handle("lpf",ControlSpec(100.0, 20000.0, 4), 2000, callback=lambda v: mmm_audio.send_float("lpf_comb", v), run_callback_on_init=True)
    layout.addWidget(lpf)

    added_space = Handle("added space",ControlSpec(0.2, 1.0), 0.0, callback=lambda v: mmm_audio.send_float("added_space", v), run_callback_on_init=True)
    layout.addWidget(added_space)

    mix_slider = Handle("mix",ControlSpec(0.1, 1.0, 0.5), 0.2, callback=lambda v: mmm_audio.send_float("mix", v), run_callback_on_init=True)
    layout.addWidget(mix_slider)

    # Set the layout for the main window
    window.setLayout(layout)

    # Show the window
    window.show()

    # Start the application's event loop
    app.exec()

if __name__ == "__main__":
    main()