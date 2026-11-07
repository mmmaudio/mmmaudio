"""PaulStretch is an FFT – based extreme time-stretching algorithm invented by Paul Nasca in 2006. The algorithm works similar to a granular time stretch, but each grain is analyzed by an FFT, the phase is randomized, and then transformed back to the time domain using IFFT. This results in a very smooth and ambient sound when stretching audio to extreme lengths.

This example shows how to use the PaulStretch graph in MMM-Audio to stretch audio in real-time.
You can change the stretch factor by sending different float values to the "dur_mult" parameter.
"""

from mmm_python import *
mmm_audio = MMMAudio(2048, graph_name="FFTBinDelays", package_name="examples")
mmm_audio.start_audio()

def make_delay_times(size=1025, x=5):
    """Split the `size` FFT bins into `x` random-width groups, each with its own random delay time and feedback level.

    `size` must equal window_size // 2 + 1 in FFTBinDelays.mojo (1025 for a 2048 window).
    """
    rand_vals = [rrand(0, 1) for _ in range(x)]
    total = sum(rand_vals)
    # cumulative group boundaries, so the group widths always add up to exactly `size`
    bounds = [0]
    running = 0.0
    for v in rand_vals:
        running += v / total
        bounds.append(round(running * size))
    bounds[-1] = size
    delay_times = []
    feedback = []
    for i in range(x):
        width = bounds[i + 1] - bounds[i]
        delay_times.extend([int(rrand(0, 200))] * width)
        feedback.extend([rrand(0.5, 0.7)] * width)
    return delay_times, feedback

if True:
    delay_times, feedback = make_delay_times()
    mmm_audio.send_ints("delay_times", delay_times)
    mmm_audio.send_floats("feedback", feedback)

mmm_audio.stop_audio()