"""
An example of Vector Base Amplitude Panning. Inclues a 4 channel speaker array example where speakers are placed at azimuths of -55, 55, -110, and 110 degrees. Also includes a 7-channel surround sound example.

The position of the audio source is controlled by the mouse. The corners of the screen are positioned directly on top of the speakers.
"""

from mmm_python import *
from math import pi
# instantiate and load the graph
mmm_audio = MMMAudio(128, num_output_channels=11, graph_name="VectorBasePanning3D", package_name="examples")


mmm_audio.start_audio()
degrees_to_radians = pi/180

mmm_audio.send_float("az", -0.45 * pi)
mmm_audio.send_float("ht", -0.2 * 2 * pi)
mmm_audio.send_float("az", -0.25  * pi)
# mmm_audio.send_float("az", 0.375 * 2 * pi)
# mmm_audio.send_float("az", 0.5 * 2 * pi)
# mmm_audio.send_float("az", 0.625 * 2 * pi)
# mmm_audio.send_float("az", 0.75 * 2 * pi)
# mmm_audio.send_float("az", 0.875 * 2 * pi)
mmm_audio.send_float("az", 185 * degrees_to_radians + (1.0 * pi))


#Enable/disable mouse
mmm_audio.send_bool("mouse", True)
mmm_audio.send_bool("mouse", False)

# for Wayland use the fake mouse
MMMAudio.fake_mouse()

mmm_audio.stop_audio()

mmm_audio.plot(48000)

# This implementation of VBAP uses the Quickhull algorithm to determine speaker triplets. For further explanantion see this paper by Hongchan Choi: https://repository.gatech.edu/atmire-ds/25e3c444-6cde-4c2b-a4e0-f015cb46211c/page/2
# Executing the code below shows a 3d representation of all speaker triplets.


# A 7.1.4 Atmos Array (azimuth positions in degrees)
speaker_positions = [
    
    [0.0, 0],#Center
    [25, 0],# L
    [-25, 0],# R
    [90, 0], # LS
    [-90, 0], # RS
    [135 , 0], # LB
    [-135, 0], # RB
    [40, 35], #LTF
    [-40, 35], #RTF
    [120, 35], #LTR
    [-120, 35] #RTF

]

from mmm_python.Helpers import SpeakerHelper

SpeakerHelper.save_array(speaker_positions, "tmp/7-1-4-atmos.json", to_radians=True)

SpeakerHelper.show_vbap3d_array(SpeakerHelper.load_array("tmp/7-1-4-atmos.json"))


