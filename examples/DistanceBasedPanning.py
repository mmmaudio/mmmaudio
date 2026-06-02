"""
An example of Distance Based Amplitude Panning in a 4 channel speaker array where speakers are placed at (-1, 1), (1, 1), (-1,-1) and (1, -1) meters.

The position of the audio source is controlled by the mouse. The corners of the screen are positioned directly on top of the speakers.
"""

from mmm_python import * 

# instantiate and load the graph
mmm_audio = MMMAudio(128, num_output_channels=4, graph_name="DistanceBasedPanning", package_name="examples")


mmm_audio.start_audio()

# for Wayland use the fake mouse
MMMAudio.fake_mouse()

mmm_audio.stop_audio()

mmm_audio.plot(48000)