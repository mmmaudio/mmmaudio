"""Example showing how to create a variable number of UGens in MMM-Audio. In the ManyOscillators.mojo file, the ManyOscillators struct holds a List of OscillatorPair structs. Each OscillatorPair contains two oscillators (sine wave generators) that can be detuned from each other. We can dynamically change the number of oscillator pairs by sending an integer message to the "num_pairs" parameter.

The slider sets "num_pairs", from 2 to 200.
"""
import sys
from pathlib import Path

# Add the MMMAudio folder to the path, so this file can be run from anywhere.
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *

def main():
    mmm_audio = MMMAudio(128, graph_name="ManyOscillators", package_name="examples.export_examples")
    mmm_audio.start_audio()

    app = QApplication([])

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Many Oscillators")
    window.resize(300, 50)
    # stop audio when window is closed
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    layout = QVBoxLayout()

    num_pairs_slider = Handle("num_pairs", ControlSpec(2, 200, 1), 10, callback=lambda v: mmm_audio.send_int("num_pairs", round(v)), run_callback_on_init=True)
    layout.addWidget(num_pairs_slider)

    window.setLayout(layout)
    window.show()
    app.exec()

if __name__ == "__main__":
    main()
