"""
An example of Vector Base Amplitude Panning in a 4 channel speaker array where speakers are placed at azimuths of -55, 55, -110, and 110 degrees.

The position of the audio source is controlled by the mouse. The corners of the screen are positioned directly on top of the speakers.
"""

from mmm_python import *
from math import pi
# instantiate and load the graph
mmm_audio = MMMAudio(128, num_output_channels=4, graph_name="VectorBasedPanning", package_name="examples")



mmm_audio.start_audio()

mmm_audio.send_float("az", 0.0 * 2 * pi)
mmm_audio.send_float("az", 0.125 * 2 * pi)
mmm_audio.send_float("az", 0.25 * 2 * pi)
mmm_audio.send_float("az", 0.375 * 2 * pi)
mmm_audio.send_float("az", 0.5 * 2 * pi)
mmm_audio.send_float("az", 0.625 * 2 * pi)
mmm_audio.send_float("az", 0.75 * 2 * pi)
mmm_audio.send_float("az", 0.875 * 2 * pi)

# for Wayland use the fake mouse
MMMAudio.fake_mouse()



# For WSL
def wsl_fake_mouse(instance, x_size: int = 300, y_size: int = 300):
    """Create a GUI slider that sends fake mouse positions to all instances."""
    from mmm_python.GUI import Slider2D
    from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout
    from math import atan2
    instance.send_int("wsl", 1)
    # Use existing QApplication if it exists, otherwise create a new one
    app = QApplication.instance()
    if app is None:
        app = QApplication([])
        app_created = True
    else:
        app_created = False

    app.quitOnLastWindowClosed = True 

    # Create the main window
    window = QWidget()
    window.setWindowTitle("Fake Mouse Position Controller")
    window.resize(int(x_size), int(y_size))

    # Create layout
    layout = QVBoxLayout()

    slider2d = Slider2D(x_size, y_size)

    def on_slider_change(x, y):
        # Send to all MMMAudio instances
        
        instance.send_floats("pos", [y * 2 - 1, x * 2 - 1])

    slider2d.value_changed.connect(on_slider_change)
    layout.addWidget(slider2d)
    window.setLayout(layout)
    window.show()

    # Only run exec() if we created the app (no existing event loop)
    if app_created:
        app.exec()
    
    return window  # Return window so it can be kept alive if needed


wsl_fake_mouse(mmm_audio)

mmm_audio.send_int("wsl", 0)

mmm_audio.stop_audio()

mmm_audio.plot(48000)