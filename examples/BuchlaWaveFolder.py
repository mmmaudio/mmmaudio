"""This example demonstrates the Buchla 259-style wavefolder distortion on a sine wave.

The Buchla Wavefolder is a classic wave-shaping synthesis technique that adds harmonic complexity to audio signals by folding the waveform back on itself when it exceeds certain thresholds. This results in a rich, complex sound often used in electronic music synthesis. Derived from "Virual Analog Buchla 259e Wavefolder" by Esqueda, etc.

Use the BuchlaWaveFolder_AD version for Anti-aliasing (ADAA) and Downsampler. The ADAA technique is based on Jatin Chowdhury's chow_dsp waveshapers.

It is recommended to plot the output waveform to get a sense of how the wavefolding process alters the sound."""

from mmm_python import *

# instantiate and load the graph
mmm_audio = MMMAudio(128, graph_name="BuchlaWaveFolder_AD", package_name="examples")

# to hear the version without Anti-aliasing, use:
# mmm_audio = MMMAudio(128, graph_name="BuchlaWaveFolder", package_name="examples")
mmm_audio.start_audio() 

mmm_audio.stop_audio()
mmm_audio.plot(4000)
