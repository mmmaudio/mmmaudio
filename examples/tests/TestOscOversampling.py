from mmm_python import *

# instantiate and load the graph
mmm_audio = MMMAudio(128, graph_name="TestOscOversampling", package_name="examples.tests")
mmm_audio.start_audio() 

mmm_audio.send_float("which", 0.0) # none
mmm_audio.send_float("which", 1.0) # 2x
mmm_audio.send_float("which", 2.0) # 4x
mmm_audio.send_float("which", 3.0) # 8x
mmm_audio.send_float("which", 4.0) # 16x
mmm_audio.send_float("which", 5.0) # 16x in an oversampling loop

mmm_audio.stop_audio()  