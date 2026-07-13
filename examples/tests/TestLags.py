from mmm_python import *


# instantiate and load the graph
mmm_audio = MMMAudio(128, graph_name="TestLags", package_name="examples.tests")
mmm_audio.start_audio() 


mmm_audio.stop_audio()