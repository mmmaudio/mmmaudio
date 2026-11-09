"""A GUI for NessStretchGUI.mojo, which wraps examples/NessStretch.mojo so it can be exported as a plugin.

NessStretch is an FFT-based extreme time-stretching algorithm invented by Alex Ness and
based on Paul Nasca's PaulStretch. It stretches the lowest octave with a 65536 point FFT
and the highest with a 256 point FFT, which keeps more detail and smears transients less.

The "dur_mult" slider sets how many times longer the file plays (1 to 1000). The
"choose file" button picks a .wav file to stretch.
"""
import sys
from pathlib import Path

# Add the MMMAudio folder to the path, so this file can be run from anywhere.
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *
from PySide6.QtWidgets import QFileDialog


def main():
    mmm_audio = MMMAudio(2048, graph_name="NessStretchGUI", package_name="Exporters.export_examples")
    mmm_audio.start_audio()

    app = QApplication([])

    window = QWidget()
    window.setWindowTitle("NessStretch")
    window.resize(400, 100)
    # stop audio when window is closed
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    layout = QVBoxLayout()

    # 40 is the default in examples/NessStretch.mojo
    dur_mult = Handle("dur_mult", ControlSpec(1.0, 1000.0, 3.0), 40.0,
                      callback=lambda v: mmm_audio.send_float("dur_mult", v),
                      resolution=10000, display_resolution=1, run_callback_on_init=True)
    layout.addWidget(dur_mult)

    def choose_file():
        path, _ = QFileDialog.getOpenFileName(window, "Choose a file to stretch", "", "WAV files (*.wav)")
        if path:
            mmm_audio.send_string("file", path)

    file_button = QPushButton("choose file")
    file_button.clicked.connect(choose_file)
    layout.addWidget(file_button)

    window.setLayout(layout)
    window.show()
    app.exec()


if __name__ == "__main__":
    main()
