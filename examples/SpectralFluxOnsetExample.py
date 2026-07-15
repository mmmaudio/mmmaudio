"""
This example demonstrates using SpectralFluxOnsets to detect onsets in an audio file.
The audio plays in the left channel and onset impulses are heard in the right channel.
"""

from mmm_python import *
ma = MMMAudio(128, graph_name="SpectralFluxOnsetExample", package_name="examples")
ma.start_audio()

# Adjust threshold for onset sensitivity (lower = more sensitive)
ma.send_float("thresh", 10)
# Adjust minimum slice length between onsets (higher = less sensitive)
ma.send_float("minSliceLength", 0.3)  

# Adjust impulse volume
ma.send_float("impulse_vol", 0.5)

ma.stop_audio()
