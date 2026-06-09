"""
An example of Distance Based Amplitude Panning in a 4 channel speaker array where speakers are placed at (-1, 1), (1, 1), (-1,-1) and (1, -1) meters.

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

mmm_audio.stop_audio()

mmm_audio.plot(48000)