"""
Chowning FM synthesis example.

These examples are adapted from Chowning's original [paper](https://web.eecs.umich.edu/~fessler/course/100/misc/chowning-73-tso.pdf) on FM synthesis and can also be found in "Computer Music" by Dodge and Jerse. pg. 123-127.
"""

from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="ChowningFM", package_name="examples")
mmm_audio.start_audio()

def play_chowning(m_freq, c_freq, amp_vals, amp_times, index_vals, index_times, amp_curves=None, index_curves=None):
    """Send all FM parameters and trigger a note. Curves default to 1 for every segment."""
    if amp_curves is None:
        amp_curves = [1] * len(amp_times)
    if index_curves is None:
        index_curves = [1] * len(index_times)
    mmm_audio.send_float("m_freq", m_freq)
    mmm_audio.send_float("c_freq", c_freq)
    mmm_audio.send_floats("amp_vals", amp_vals)
    mmm_audio.send_floats("amp_times", amp_times)
    mmm_audio.send_floats("amp_curves", amp_curves)
    mmm_audio.send_floats("index_vals", index_vals)
    mmm_audio.send_floats("index_times", index_times)
    mmm_audio.send_floats("index_curves", index_curves)
    mmm_audio.send_trig("trigger")

# bell
play_chowning(m_freq=280.0, c_freq=200.0,
        amp_vals=[0.0, 1.0, 0.2, 0.0], amp_times=[0.001, 1.8, 1.7],
        index_vals=[10.0, 2.0, 0.0], index_times=[1.8, 1.7])

# woodblock
play_chowning(m_freq=55.0, c_freq=80.0,
        amp_vals=[0.75, 1.0, 0.6, 0.2, 0.0], amp_times=[0.02, 0.02, 0.06, 0.1],
        index_vals=[25.0, 0.0], index_times=[0.012])

# brass
play_chowning(m_freq=440.0, c_freq=440.0,
        amp_vals=[0, 1, 0.7, 0.7, 0], amp_times=[0.075, 0.050, 0.4, 0.06],
        index_vals=[0, 5, 3.5, 3.5, 0], index_times=[0.075, 0.050, 0.4, 0.06])

# brass (less bright)
play_chowning(m_freq=440.0, c_freq=440.0,
        amp_vals=[0, 1, 0.7, 0.7, 0], amp_times=[0.075, 0.050, 0.4, 0.06],
        index_vals=[0, 3, 2.1, 2.1, 0], index_times=[0.075, 0.050, 0.4, 0.06])

# clarinet
play_chowning(m_freq=600.0, c_freq=900.0,
        amp_vals=[0, 1, 1, 0], amp_times=[0.087, 0.4, 0.087],
        index_vals=[4, 2], index_times=[0.073])

# stop audio
mmm_audio.stop_audio()