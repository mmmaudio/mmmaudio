"""
Demonstrates granular synthesis using TGrains, using a mouse to control granular playback.

Left and right moves around in the buffer. Up and down controls rate of triggers.
"""

from mmm_python import *
mmm_audio = MMMAudio(128, num_output_channels = 8, graph_name="Grains", package_name="examples")
mmm_audio.start_audio() 

# for Wayland use the fake mouse
MMMAudio.fake_mouse()

# when using a user defined env, setting the grain envelope should change the sound dramatically
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.01, 1.0, 1.0, 0.0]) 
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.5, 1.0, 1.0, 0.0])
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.1, 1.0, 0.2, 0.75, 0.8, 0.75, 1.0,0.0]) 

# this will increase the trig rate, but there won't be enough grains
# so increase the number of grains
mmm_audio.send_float("max_trig_rate", 80.0) 
mmm_audio.send_int("set_num_grains", 40)

mmm_audio.stop_audio()

# the below version is the same except it uses a custom grain with a BandPass filter embedded directly in the grain

from mmm_python import *
mmm_audio = MMMAudio(128, num_output_channels = 2, graph_name="Grains_Custom", package_name="examples")
mmm_audio.start_audio() 

# setting the grain envelope should change the sound dramatically
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.01, 1.0, 1.0, 0.0]) 
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.5, 1.0, 1.0, 0.0])
mmm_audio.send_floats("env_points", [0.0, 0.0, 0.1, 1.0, 0.2, 0.75, 0.8, 0.75, 1.0,0.0]) 

MMMAudio.get_audio_devices()

dbamp(-120)