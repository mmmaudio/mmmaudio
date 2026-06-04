from mmm_python import *
from random import getstate, setstate, randint
mmm_audio = MMMAudio(128, graph_name="PAF_example", package_name="examples", in_device=None, audio_init_timeout=60)
mmm_audio.start_audio()

mmm_audio.send_float("center_freq", 200)
mmm_audio.send_float("bandwidth", 800)

mmm_audio.send_float("center_freq", rrand(10, 2000))
mmm_audio.send_float("bandwidth", rrand(10, 2000))


# repetetive random sequence
async def loop():

    # get initial state
    state1 = getstate()
    while True:
        # get new second state (different each time)
        state2 = getstate()
        # loop through same first state x times with constant subdivision
        for _ in range(randint(2, 12)):
            setstate(state1)
            for _ in range(randint(3, 15)):
                mmm_audio.send_float("fundamental", midicps(randint(40, 80)))
                mmm_audio.send_trig("trig")
                await asyncio.sleep(0.1)
        # loop through second state const num of times with changing subdivision
        for _ in range(randint(2, 12)):
            setstate(state2)

            for _ in range(randint(3, 15)):
                mmm_audio.send_float("fundamental", midicps(randint(40, 80)))
                mmm_audio.send_trig("trig")
                await asyncio.sleep(0.1)

s = Scheduler()

fut = s.sched(loop())
fut.cancel()
mmm_audio.stop_audio()
