"""Example showing how to create a variable number of UGens in MMM-Audio. In the ManyOscillators.mojo file, the ManyOscillators struct holds a List of OscillatorPair structs. Each OscillatorPair contains two oscillators (sine wave generators) that can be detuned from each other. We can dynamically change the number of oscillator pairs by sending an integer message to the "num_pairs" parameter.

"""

from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="ManyOscillators", package_name="examples")
mmm_audio.start_audio()

mmm_audio.send_int("num_pairs", 2)  # set to 2 pairs of oscillators

mmm_audio.send_int("num_pairs", 14)  # change to 14 pairs of oscillators

mmm_audio.send_int("num_pairs", 1000)  # change to 1000 pairs of oscillators

mmm_audio.stop_audio() # stop/pause the audio thread
