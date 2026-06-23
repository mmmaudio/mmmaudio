"""
This example demonstrates the Dattorro Reverb graph, which is a reverb algorithm created by Jon Dattorro in his paper "Effect Design Part 1: Reverberator and Other Filters". 
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python.GUI import Handle, ControlSpec
from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QCheckBox

from mmm_python import *

def add_handle(layout, mmm_audio, name: str, min: float, max: float, exp: float, default: float, resolution: float, display_resolution: int):
    """Create a slider and connect it to the audio graph."""
    slider = Handle(name, ControlSpec(min, max, exp), default, callback=lambda v: mmm_audio.send_float(name, v), resolution = resolution, display_resolution = display_resolution)
    layout.addWidget(slider)
    mmm_audio.send_float(name, default)

def main():
    # instantiate and load the graph
    m_a = MMMAudio(128, 2, graph_name="DattorroReverbExample", package_name="examples")
    m_a.send_int("in_chan", 0)
    m_a.start_audio()

    app = QApplication([])

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Dattorro Reverb")
    window.resize(300, 100)
    # stop audio when window is closed
    window.closeEvent = lambda event: (m_a.exit_all(), event.accept())

    # Create layout
    layout = QVBoxLayout()
    # Add all the controls
    add_handle(layout, m_a, "pre_delay_time", 0.0, 0.5, 1.0, 0.00, 10000, 6)
    add_handle(layout, m_a, "decay", 0.001, 1.0, 1.0, 0.83, 10000, 6)
    add_handle(layout, m_a, "input_diffusion1", 0.0, 1.0, 1.0, 0.81, 10000, 6)
    add_handle(layout, m_a, "input_diffusion2", 0.0, 1.0, 1.0, 0.66, 10000, 6)
    add_handle(layout, m_a, "decay_diffusion1", 0.0, 1.0, 1.0, 0.43, 10000, 6)
    add_handle(layout, m_a, "decay_diffusion2", 0.0, 1.0, 1.0, 0.81, 10000, 6)
    add_handle(layout, m_a, "bandwidth", 0.0, 1.0, 1.0, 0.3, 10000, 6)
    add_handle(layout, m_a, "damping", 0.0, 1.0, 1.0, 0.004, 10000, 6)

    # Set the layout for the main window
    window.setLayout(layout)

    # Show the window
    window.show()

    # Start the application's event loop
    sys.exit(app.exec())

if __name__ == "__main__":
    main()