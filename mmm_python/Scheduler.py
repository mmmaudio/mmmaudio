import asyncio
import contextvars
import threading
import time

# Each routine's logical time: when its last wait was due, on the event loop's clock.
# Every task gets its own copy of a ContextVar, so each routine keeps a separate clock.
_logical_time = contextvars.ContextVar("logical_time", default=None)

class Scheduler:
    """The main Scheduler class for the Python side of MMMAudio. Can be used to run asyncio coroutines in a separate scheduling thread. This has the advantage of not blocking the main thread, but also allows for each schedule to be cancelled individually."""

    def __init__(self):
        """Initialize the Scheduler. Also starts the asyncio event loop in its own unique thread."""
        self.loop = None
        self.thread = None
        self.running = False
        self.routines = []
        self.wait_mult = 1.0

        self.start_thread()

    async def wait(self, delay):
        """Coroutine that waits `delay` seconds after the routine's previous wait was due, rather than after now.

        Always use `await sched.wait(delay)` instead of `await asyncio.sleep(delay)` inside routines started with `sched`. If a wait wakes up late, the next one is shortened by the same amount, so a routine that waits between its events never drifts from its intended timing. 

        Args:
            delay: Time in seconds after the previous wait was due. Scaled by `wait_mult`.
        """
        loop = asyncio.get_running_loop()
        start = _logical_time.get()
        if start is None:  # not started by sched, so time from now
            start = loop.time()
        target = start + delay * self.wait_mult
        _logical_time.set(target)
        await asyncio.sleep(max(target - loop.time(), 0))

    async def _run(self, coro):
        """Start a routine's logical clock at the current time, then run it."""
        _logical_time.set(asyncio.get_running_loop().time())
        return await coro

    def start_thread(self):
        """Create a new asyncio event loop and run it in a separate scheduling thread."""
        def run_event_loop():
            self.loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self.loop)
            self.running = True
            print(f"Asyncio thread started: {threading.get_ident()}")
            
            try:
                self.loop.run_forever()
            finally:
                self.loop.close()
                self.running = False
                print(f"Asyncio thread stopped: {threading.get_ident()}")
        
        if self.thread is not None and self.thread.is_alive():
            return self.thread

        self.thread = threading.Thread(target=run_event_loop, daemon=False)

        self.thread.start()
        
        # Wait for the loop to be ready
        while not self.running:
            time.sleep(0.01)

        return self.thread
    
    def sched(self, coro):
        """Add a coroutine to the running event loop.

        Args:
            coro: The coroutine to be scheduled.
        
        Returns:
            The Future object representing the scheduled coroutine. This returned object can be used to check the status of the coroutine, retrieve its result, or stop the coroutine when needed.
        """

        # any time a new event is scheduled, clear the routs list of finished coroutines

        for i in range(len(self.routines)-1,-1,-1):
            if self.routines[i].done():
                del self.routines[i]

        if not self.running or not self.loop:
            raise RuntimeError("Asyncio thread is not running")
        
        rout = asyncio.run_coroutine_threadsafe(self._run(coro), self.loop)
        self.routines.append(rout)

        return rout

    def stop_routs(self):
        """Stop all running routines."""
        for rout in self.routines:
            rout.cancel()
        self.routines.clear()

    def get_routs(self):
        """Get all running routine."""
        return self.routines

    def stop_thread(self):
        """Stop the asyncio event loop and thread and start a new one."""
        if self.loop and self.running:
            self.loop.call_soon_threadsafe(self.loop.stop)
            if self.thread:
                self.thread.join(timeout=5)
        self.start_thread()

from mmm_python import MMMAudio
import json

import functools

def process_nrt_event(event, targets, verbose=False):
    if verbose:
        print(f"Callback received event: {event}")

    obj_name, method_name = event["message"].split(".", 1)
    target = targets[obj_name]
    func = getattr(target, method_name)
    if "key" in event and "value" in event:
        func(event["key"], event["value"])
    elif "value" in event:
        func(event["value"])

class NRT():
    """Class for handling non-realtime (NRT) processing in MMMAudio. This class provides a static method to save audio output to a WAV file while processing events from a json score file."""

    @staticmethod
    def save_to_wav(mmm_audio: MMMAudio, filename, duration_seconds=200, score_path=None, targets=None, verbose=False):
        """Save audio output to a WAV file while processing events from a json score file.

        Args:
            mmm_audio: The MMMAudio instance to get audio samples from. Do not call mmm_audio.start_audio() before calling this function, as sample allocation will be handled internally.
            filename: The name of the output WAV file.
            duration_seconds: The duration of the output audio in seconds.
            score_path: Optional path to a json score file containing events to process during audio generation.
            targets: Optional dictionary mapping object names to their corresponding instances for event processing. Usually this will be a dictionary of MMMAudio instances.
            verbose: If True, print progress and event processing information.

        """

        import wave
        import numpy as np

        blocksize = mmm_audio.blocksize
        sample_rate = mmm_audio.sample_rate.value

        num_loops = int((duration_seconds * sample_rate) / blocksize)

        events = []
        if score_path:
            with open(score_path, "r", encoding="utf-8") as f:
                events = json.load(f)
        
        events.sort(key=lambda e: e["time"])
        
        current_event_index = 0

        with wave.open(filename, "wb") as wav_file:
            wav_file.setparams((mmm_audio.num_output_channels, 4, sample_rate, 0, "NONE", "not compressed"))
            for i in range(num_loops):
                current_time = i * (blocksize / sample_rate)
                while current_event_index < len(events) and events[current_event_index]["time"] <= current_time:
                    event = events[current_event_index]
                    if targets:
                        process_nrt_event(event, targets, verbose=verbose)
                    current_event_index += 1
                if verbose and i % 10 == 0:
                    print(f"Generating {filename}: {i}/{num_loops} blocks processed...")
                chunk = mmm_audio.get_samples(blocksize)
                scaled_chunk = (chunk * 2147483647).astype(np.int32)
                binary_bytes = scaled_chunk.tobytes()
                wav_file.writeframesraw(binary_bytes)

        print(f"Successfully generated {filename} as 32-bit float!")