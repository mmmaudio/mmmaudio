"""
MLP_Synth played with a Slider2D instead of the mouse.

Runs as a script: `pixi run python examples/ML_examples/MLP_Synth2D.py` from the MMMAudio folder.
Closing the window stops the audio.

The slider's x and y (each 0 to 1) are sent to the graph as "xy" and become the two inputs of
the MLP trained by MLP_Synth.py, which maps them to the synth's fourteen parameters. To
train a new mapping, use the trainer in MLP_Synth.py; this graph loads the same file,
examples/ML_examples/nn_trainings/mlp_example_training.safetensors.

This example was added because it shows how an exported plugin can include a model and its weights in the plugin bundle, so it can run without any extra files. See PluginExport.py for how to export as a VST/etc plugin.
"""

import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the MMMAudio folder to the path
# (the next line here) so that it can find the mmm_python package.
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *
from mmm_python.GUI import Slider2D
from PySide6.QtWidgets import QApplication, QLabel, QVBoxLayout, QWidget


def main():
    m_a = MMMAudio(128, in_device=None, graph_name="MLP_Synth2D", package_name="examples.ML_examples")
    m_a.send_floats("xy", [0.5, 0.5])  # the slider's starting position
    # this one is a bit intense, so maybe start with a low volume
    m_a.start_audio()

    app = QApplication([])

    window = QWidget()
    window.setWindowTitle("MLP Synth")
    # stop audio when window is closed
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())

    layout = QVBoxLayout()
    layout.addWidget(QLabel("drag to play the synth"))
    slider = Slider2D(300, 300)
    slider.set_values(0.5, 0.5)
    slider.valueChanged.connect(lambda x, y: m_a.send_floats("xy", [x, y]))
    layout.addWidget(slider)
    window.setLayout(layout)

    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
