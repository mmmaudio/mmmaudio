from mmm_python import *
mmm_audio = MMMAudio(128, num_output_channels = 4, graph_name="TestAmpComp", package_name="examples.tests")
mmm_audio.start_audio()

mmm_audio.send_float("thresh", -17.0)
mmm_audio.send_float("ratio", 4.0)
mmm_audio.send_float("attack", 0.01)
mmm_audio.send_float("release", 0.5)
mmm_audio.send_float("knee_width", 4.0)

mmm_audio.send_int("which_out", 0)
mmm_audio.send_int("which_out", 1)

mmm_audio.stop_audio()
mmm_audio.plot(48000*2)