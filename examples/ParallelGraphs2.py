"""
MMMAudio can run multiple graphs in parallel, each in its own process and very likely on a different CPU core.
""" 

from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="ManyOscillators", package_name="examples")
mmm_audio.start_audio()

mmm_audio2 = MMMAudio(128, graph_name="MoogPops", package_name="examples")
mmm_audio2.start_audio() 

mmm_audio3 = MMMAudio(2048, graph_name="NessStretch", package_name="examples")
mmm_audio3.start_audio()

mmm_audio4 = MMMAudio(128, num_output_channels = 2, graph_name="Grains", package_name="examples")
mmm_audio4.start_audio() 

mmm_audio.send_int("num_pairs", 30)

mmm_audio3.send_float("dur_mult", 200)