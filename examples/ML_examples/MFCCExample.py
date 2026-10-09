"""
 The energy of each Mel band is visualized in the console as a series of asterisks. Also the energy of each Mel band controls the loudness of a sine tone at center frequency of its band. The result is a frequency-quantized analysis-sinusoidal-resynthesis effect.
"""

from mmm_python import *
ma = MMMAudio(128, graph_name="MFCCExample", package_name="examples.ML_examples")
ma.start_audio()

ma.send_int("update_modulus",80) # higher number = slower updates

ma.stop_audio()