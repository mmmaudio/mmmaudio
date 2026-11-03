"""For a good time, test how many oscillators you can run at once."""
"""My M5 can do 9000x15=135000 oscillators at once without distortion."""
from mmm_python import *

MMMAudio.compile(graph_name="BenchmarkNumberOsc", package_name="examples.tests.benchmarks")

m_as = []
for _ in range(15):
    mmm_audio = MMMAudio(128, graph_name="BenchmarkNumberOsc", package_name="examples.tests.benchmarks")
    mmm_audio.start_audio()
    m_as.append(mmm_audio)

# below shows how groups of Osc[8] are by far the most efficient

for mmm_audio in m_as:
    mmm_audio.send_int("which", 0)
for mmm_audio in m_as:
    mmm_audio.send_int("which", 1)
for mmm_audio in m_as:
    mmm_audio.send_int("which", 2)
for mmm_audio in m_as:
    mmm_audio.send_int("which", 3)