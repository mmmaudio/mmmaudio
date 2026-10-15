from mmm_python import *

mmm_audio = MMMAudio(128, graph_name="TestHilbert", package_name="examples.tests")
mmm_audio.start_audio()

mmm_audio.send_float("freq", 150)
mmm_audio.send_float("radians", 0.0)
mmm_audio.send_float("radians", pi/2.0)
mmm_audio.send_float("radians", pi)
mmm_audio.send_float("radians", 3*pi/2.0)

mmm_audio.stop_audio()
mmm_audio.plot(2048)
