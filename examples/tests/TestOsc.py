from mmm_python import *

MMMAudio.compile(graph_name="TestOsc", package_name="examples.tests")

m_as = []
for _ in range(8):
    mmm_audio = MMMAudio(128, graph_name="TestOsc", package_name="examples.tests")
    mmm_audio.start_audio()
    m_as.append(mmm_audio)

mmm_audio.send_int("which", 0)
mmm_audio.send_int("which", 1)
mmm_audio.send_int("which", 2)
mmm_audio.send_int("which", 3)
