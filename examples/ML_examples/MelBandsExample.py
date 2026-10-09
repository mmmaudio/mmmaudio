"""
 The energy of each Mel band is visualized in the console as a series of asterisks. Also the energy of each Mel band controls the loudness of a sine tone at center frequency of its band. The result is a frequency-quantized analysis-sinusoidal-resynthesis effect.
"""

from mmm_python import *
ma = MMMAudio(128, graph_name="MelBandsExample", package_name="examples.ML_examples")
ma.start_audio()

ma.send_float("viz_mul",300.0) # 300 is the default in Mojo also
ma.send_float("sines_vol",-36.0) # db
ma.send_float("mix",1.0) 
ma.send_float("mix",0.0)
ma.send_float("mix",0.7)
ma.send_int("update_modulus",80) # higher number = slower updates

ma.stop_audio()