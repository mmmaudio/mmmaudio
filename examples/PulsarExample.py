"""
A Pulsar oscillator played with the mouse (see Pulsar in mmm_audio/Synthesizers.mojo and PulsarExample.mojo).

Pulsar squeezes one cycle of a waveform into the first `width` of each period and holds
it at the end of its cycle for the rest. The pitch stays where it is, but the squeezed
waveform pushes the energy up into a formant. Narrowing the width sounds like a
filter opening and eventually becomes a click train.

  * Mouse left/right: width, from 0.01 (left edge) to 1.0 (right edge, a plain waveform).
  * Mouse up/down: pitch, from 40 Hz (bottom) to 1000 Hz (top).

Run the first three lines, then move the mouse.
"""

from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="PulsarExample", package_name="examples")

mmm_audio.plot(500)
mmm_audio.start_audio()

# crossfade the waveform: 0 = sine, 0.33 = triangle, 0.67 = saw, 1 = square
mmm_audio.send_float("osc_frac", 0.0)
mmm_audio.send_float("osc_frac", 0.33)
mmm_audio.send_float("osc_frac", 0.67)
mmm_audio.send_float("osc_frac", 1.0)

mmm_audio.send_float("gain", 0.3)
mmm_audio.send_int("which", 1) #change to VWT version using the precomputed wavetable of a sinc function
mmm_audio.send_int("which", 0) #change back to the basic waveform version

mmm_audio.stop_audio()



