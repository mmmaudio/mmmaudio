"""Ring modulates 4 input channels into 2 output channels, with 2x oversampling.

The left output is input 0 times input 1, and the right output is input 2 times input 3.
"""

from mmm_python import *

# this will list available audio devices
MMMAudio.get_audio_devices()

# set your own input and output devices here, or leave them out to use the defaults
# in_device = "Fireface UCX II (24219339)"
# out_device = "Fireface UCX II (24219339)"

mmm_audio = MMMAudio(128, num_input_channels=4, num_output_channels=2, graph_name="QuadRingMod", package_name="llm.test_export")
mmm_audio.start_audio()

mmm_audio.stop_audio()
