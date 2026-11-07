"""NessStretch is an FFT – based extreme time-stretching algorithm invented by Alex Ness and based on Paul Nasca's PaulStretch algorithm. The algorithm takes the PaulStretch to the extreme, stretching the lowest octave using a 32768 point FFT and the highest octave using a 256 point FFT, resulting in a more detailed sound with better preservation of transients and less smearing.
"""

from mmm_python import *
mmm_audio = MMMAudio(2048, graph_name="NessStretch", package_name="examples")
mmm_audio.start_audio()

# load your own file - the candier pop the better
mmm_audio.send_string("file_name", "tmp/NRO_5sec.wav")

# change how slow the audio gets stretched
mmm_audio.send_float("dur_mult", 10.0)
mmm_audio.send_float("dur_mult", 100.0)
mmm_audio.send_float("dur_mult", 40.0)
mmm_audio.send_float("dur_mult", 1000.0)

mmm_audio.stop_audio()

