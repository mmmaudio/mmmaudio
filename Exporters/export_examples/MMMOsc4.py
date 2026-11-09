"""A GUI for MMMOsc4: four oscillators, each with a frequency slider (5 to 20000 Hz)
a shape slider (0 to 1: sine, triangle, saw, square) and an fm slider (0 to 1) that
sets how much its freq input modulates it.

The sliders send their values as they show them, so MMMOsc4 uses them as they are.
With export_vcv's gui_file, they become VCV Rack knobs with the same ranges.
"""
import sys
from pathlib import Path

# Add the MMMAudio folder to the path, so this file can be run from anywhere.
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *

# These have to match the defaults in MMMOsc4.__init__.
FREQS = [110.0, 220.0, 330.0, 440.0]
SHAPE = 0.0


def main():
    # one output channel per oscillator (capped at what the audio device has)
    mmm_audio = MMMAudio(128, num_output_channels=4, graph_name="MMMOsc4", package_name="Exporters.export_examples")
    mmm_audio.start_audio()

    app = QApplication([])

    window = QWidget()
    window.setWindowTitle("MMMOsc4")
    window.resize(400, 560)
    # stop audio when window is closed
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    layout = QVBoxLayout()
    for i in range(1, 5):
        freq = Handle(f"freq{i}", ControlSpec(5.0, 20000.0, 4.0), FREQS[i - 1],
                      callback=lambda v, i=i: mmm_audio.send_float(f"freq{i}", v),
                      resolution=10000, display_resolution=1, run_callback_on_init=True)
        shape = Handle(f"shape{i}", ControlSpec(0.0, 1.0, 1.0), SHAPE,
                       callback=lambda v, i=i: mmm_audio.send_float(f"shape{i}", v),
                       run_callback_on_init=True)
        fm = Handle(f"fm{i}", ControlSpec(0.0, 1.0, 1.0), 0.0,
                    callback=lambda v, i=i: mmm_audio.send_float(f"fm{i}", v),
                    run_callback_on_init=True)
        layout.addWidget(freq)
        layout.addWidget(shape)
        layout.addWidget(fm)

    window.setLayout(layout)
    window.show()
    app.exec()


if __name__ == "__main__":
    main()
