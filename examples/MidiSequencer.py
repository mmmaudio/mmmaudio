"""
A sequenced polyphonic synthesizer controlled via a MIDI keyboard.

This example demonstrates a couple different concepts:
- How to Pseq and Pxrand from mmm_python.Patterns to create sequences of notes and other parameters.
- How to create a coroutine to schedule note triggers using the MMMAudio scheduler.

"""
if True:
    from mmm_python import *

    # instantiate and load the graph
    mmm_audio = MMMAudio(128, graph_name="MidiSequencer", package_name="examples")
    mmm_audio.start_audio()

    import numpy as np
    import asyncio

    global scheduler
    scheduler = Scheduler()

    poly_pal = PolyPal(mmm_audio, "poly", 64)
    filter_seq = Pseq([linexp(i/100, 0, 1, 100, 5000) for i in range(0, 101)] + [linexp(i/100, 0, 1, 4999, 101) for i in range(0, 101)])
    mmm_audio.send_float("filt_freq", filter_seq.next()) # update filter frequency before each note


# load the sequencer function
async def trig_synth(wait):
    """A counter coroutine"""
    count_to = np.random.choice([7, 11, 13, 17]).item()
    mult_seq = Pseq(list(range(1, count_to + 1)))
    fund_seq = Pxrand([36, 37, 43, 42])
    i = 0
    fund = midicps(fund_seq.next())
    while True:
        mmm_audio.send_float("filt_freq", filter_seq.next()) # update filter frequency before each note
        poly_pal.send_floats([fund * mult_seq.next(), 100 / 127.0])  # note freq and velocity scaled 0 to 1
        await asyncio.sleep(wait)
        
        i = (i + 1) % count_to
        
        if i == 0:
            fund = midicps(fund_seq.next())
            count_to = np.random.choice([7, 11, 13, 17]).item()
            mult_seq = Pseq(list(range(1, count_to + 1)))

# start the routine with the scheduler
rout = scheduler.sched(trig_synth(0.05))
rout.cancel() # stop just this routine

# stop all routines
scheduler.stop_routs() # you can also stop the routines with ctl-C in the terminal

mmm_audio.stop_audio()
mmm_audio.start_audio()
