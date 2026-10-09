"""
A sine wave pushed through four Chebyshev waveshaping curves.

The four curves live in the channels of one Buffer, built by a single
`cheby_fill` call that takes one amplitude list per channel.
Moving the mouse from the left edge of the screen to the right
crossfades between them, so the sound gets brighter as you go right.

The WaveShaper runs at 2x oversampling, which is what keeps the harmonics it
generates from folding back down the spectrum.

Run the first three lines, then move the mouse.
"""

from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="ChebyShaper", package_name="examples")
mmm_audio.start_audio()

# Move the mouse left to right to sweep from the 2 harmonic curve to the 5
# harmonic one.

mmm_audio.send_float("freq", 55.0)
mmm_audio.send_float("freq", 220.0)
mmm_audio.send_float("freq", 440.0)

# Drive the crossfade from here instead of the mouse - useful on Wayland, where
# global mouse tracking often does not work.
mmm_audio.send_bool("mouse", False)
mmm_audio.send_float("dist_frac", 0.0)   # 2 harmonics
mmm_audio.send_float("dist_frac", 0.33)  # 3 harmonics
mmm_audio.send_float("dist_frac", 0.67)  # 4 harmonics
mmm_audio.send_float("dist_frac", 1.0)   # 5 harmonics

# back to the mouse
mmm_audio.send_bool("mouse", True)

mmm_audio.stop_audio()
