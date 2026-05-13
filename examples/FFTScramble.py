from mmm_python import *

mmm_audio = MMMAudio(
    in_device=None,
    out_device='BlackHole 2ch',
    blocksize=128, 
    graph_name="FFTScramble", 
    package_name="examples"
    )

mmm_audio.start_audio()

mmm_audio.send_int("n_scrambles",100)
mmm_audio.send_int("scramble_range",40)

mmm_audio.send_trig("scramble")

mmm_audio.stop_audio()