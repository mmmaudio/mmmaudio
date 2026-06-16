import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python import *

from mmm_python.GUI import Handle, ControlSpec
from mmm_python import *
from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QCheckBox


app = QApplication([])

def main():
    mmm_audio = MMMAudio(128, graph_name="FM4", package_name="examples")
    mmm_audio.start_audio()

    sliders = []
    # Create the main window
    window = QWidget()
    window.setWindowTitle("FM4")
    window.resize(600, 100)

    # Create main horizontal layout
    main_layout = QHBoxLayout()

    layouts = []
    
    # Create left vertical layout
    layouts.append(QVBoxLayout())
    layouts[0].setSpacing(0)
    
    # Create right vertical layout
    layouts.append(QVBoxLayout())
    layouts[1].setSpacing(0)
    
    # Add both layouts to the main horizontal layout
    main_layout.addLayout(layouts[0])
    main_layout.addLayout(layouts[1])

    def add_handle(name: str, min: float, max: float, exp: float, default: float, layout_index: int = 0, resolution: int = 1000):
        # make the slider
        slider = Handle(name, ControlSpec(min, max, exp), default, callback=lambda v: mmm_audio.send_float(name, v))
        sliders.append(slider)
        # add it to the layout
        layouts[layout_index].addWidget(slider)
        # send the default value to the graph
        mmm_audio.send_float(name, default)

    add_handle("osc0_freq", 0.2, 4000.0, 0.125, 100)
    add_handle("osc1_freq", 0.2, 4000.0, 0.125, 10)
    add_handle("osc2_freq", 0.2, 4000.0, 0.125, 10)
    add_handle("osc3_freq", 0.2, 4000.0, 0.125, 10)

    add_handle("osc0_mula", 0, 3000.0, 1, 0)
    add_handle("osc0_mulb", 0, 3000.0, 1, 0)

    add_handle("osc1_mula", 0, 3000.0, 1, 0)
    add_handle("osc1_mulb", 0, 3000.0, 1, 0)
    add_handle("osc2_mula", 0, 3000.0, 1, 0)
    add_handle("osc2_mulb", 0, 3000.0, 1, 0)

    add_handle("osc3_mula", 0, 3000.0, 1, 0, 1)
    add_handle("osc3_mulb", 0, 3000.0, 1, 0, 1)

    add_handle("osc_frac0", 0, 1.0, 1, 0, 1, 4)
    add_handle("osc_frac1", 0, 1.0, 1, 0, 1, 4)
    add_handle("osc_frac2", 0, 1.0, 1, 0, 1, 4)
    add_handle("osc_frac3", 0, 1.0, 1, 0, 1, 4)

    button  = QPushButton("randomize")
    button.clicked.connect(lambda: [s.set_value(s.spec.unnormalize(rrand(0.0001, 1.0))) for s in sliders])

    layouts[1].addWidget(button)

    # window.closeEvent = lambda event: (app.quit())
    # Set the layout for the main window
    window.closeEvent = lambda event: (MMMAudio.exit_all(), event.accept())
    window.setLayout(main_layout)
    # Show the window
    window.show()
    window.raise_()

    # Start the application's event loop
    app.exec()

if __name__ == "__main__":
    main()

