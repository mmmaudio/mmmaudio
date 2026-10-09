"""
A sine wave folded through the Lockhart wavefolder using the WaveShaper.

The transfer curve is the virtual analog model from Esqueda, Pontynen,
Valimaki and Bilbao, "Virtual Analog Models of the Lockhart and Serge
Wavefolders" (Applied Sciences 7(12), 2017), Equation 26, evaluated into a one
channel Buffer by `lockhart_fill` in `llm/functions.mojo` and read as a
waveshaping table.

The drive of the sine through the WaveShaper is the distortion control.

The curve only adds odd harmonics.
"""

from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="LockhartFolder", package_name="examples")
mmm_audio.start_audio()

mmm_audio.send_float("freq", 55.0)
mmm_audio.send_float("freq", 110.0)
mmm_audio.send_float("freq", 220.0)

mmm_audio.stop_audio()

mmm_audio.plot(500)