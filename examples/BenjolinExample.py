"""Rob Hordijk's Benjolin-inspired Synthesizer

Based on the [SuperCollider implementation by Hyppasus](https://scsynth.org/t/benjolin-inspired-instrument/1074/1).

Ported to MMMAudio by Ted Moore, October 2025
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python.GUI import Handle, ControlSpec
from mmm_python import *
from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QCheckBox


def add_handle(layout, mmm_audio, name: str, min: float, max: float, exp: float, default: float):
    """Create a slider and connect it to the audio graph."""
    slider = Handle(name, ControlSpec(min, max, exp), default, callback=lambda v: mmm_audio.send_float(name, v))
    layout.addWidget(slider)
    mmm_audio.send_float(name, default)


def main():
    # instantiate and load the graph
    mmm_audio = MMMAudio(
        blocksize=128, 
        graph_name="BenjolinExample", 
        package_name="examples", 
        in_device=None, 
        out_device="default"
        )
    mmm_audio.start_audio()

    app = QApplication([])

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Benjolin")
    window.resize(300, 100)
    # stop audio when window is closed
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    # Create layout
    layout = QVBoxLayout()

    # Add all the controls
    add_handle(layout, mmm_audio, "freq1", 20, 14000.0, 4, 100)
    add_handle(layout, mmm_audio, "freq2", 0.1, 14000.0, 4, 5)
    add_handle(layout, mmm_audio, "scale", 0, 1.0, 1, 0.1)
    add_handle(layout, mmm_audio, "rungler1", 0, 1.0, 1, 0.1)
    add_handle(layout, mmm_audio, "rungler2", 0, 1.0, 1, 0.1)
    add_handle(layout, mmm_audio, "runglerFiltMul", 0, 1.0, 1.0, 0.5)
    add_handle(layout, mmm_audio, "loop", 0, 1.0, 1, 0.1)
    add_handle(layout, mmm_audio, "filterFreq", 20, 20000, 4, 3000)
    add_handle(layout, mmm_audio, "q", 0.1, 8.0, 0.5, 1.0)
    add_handle(layout, mmm_audio, "gain", 0.0, 2.0, 1, 1.0)
    add_handle(layout, mmm_audio, "filterType", 0, 8, 1.0, 0.0)
    add_handle(layout, mmm_audio, "outSignalL", 0, 6, 1.0, 1.0)
    add_handle(layout, mmm_audio, "outSignalR", 0, 6, 1.0, 3.0)

    # Set the layout for the main window
    window.setLayout(layout)

    # Show the window
    window.show()

    # Start the application's event loop
    sys.exit(app.exec())


if __name__ == "__main__":
    main()