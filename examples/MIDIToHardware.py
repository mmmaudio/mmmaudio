"""Plays resources/bach.json as MIDI note on and note off messages out of the IAC Driver, using supriya_midi.
The notes are played by a coroutine running on the MMMAudio Scheduler.

bach.json is a list of events, each a time in seconds and a [note, velocity] pair:

    {"time": 1.908788, "message": "poly_pal.send_ints", "value": [65, 72]}

A velocity of 0 is a note off.

This uses IAC Driver by default, but it can be any midi hardware/software that accepts MIDI output.

On macOS, turn the IAC Driver on in Audio MIDI Setup (Window > Show MIDI Studio, double-click IAC Driver, check "Device is online"). Then anything listening to "IAC Driver Bus 1", such as a DAW or examples/MidiKeyboard.py with its port changed to 'IAC Driver Bus 1', will play the notes.

Run it from the MMMAudio root: `pixi run python examples/MIDIToHardware.py`. Ctrl+C stops it and turns off any notes still sounding.
"""

import asyncio
import json
import sys
import time
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_python package.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python.Scheduler import Scheduler
import supriya_midi as midi

SCORE = Path(__file__).resolve().parent.parent / "resources" / "bach.json"
PORT_NAME = "IAC Driver"  # the first output port whose name contains this - change to whatever output you like
CHANNEL = 0  # MIDI channel 1 (supriya_midi counts channels from 0)


def open_output(name: str) -> midi.MidiOut:
    out = midi.MidiOut()
    ports = out.get_ports()
    matches = [i for i, port in enumerate(ports) if name in port]
    if not matches:
        raise SystemExit(f"No MIDI output named '{name}'. The outputs are: {ports}")
    out.open_port(matches[0])
    print(f"Sending to {ports[matches[0]]}")
    return out


async def play(out: midi.MidiOut, events: list, sounding: set):
    """Send each event when its time comes. Runs on the Scheduler's thread."""
    # time each event from the start, rather than sleeping between events, so the timing doesn't drift
    start = time.perf_counter()
    for event in events:
        note, velocity = event["value"]
        wait = start + event["time"] - time.perf_counter()
        if wait > 0:
            await asyncio.sleep(wait)

        if velocity > 0:
            message = midi.NoteOnMessage(channel_id=CHANNEL, note_number=note, velocity=velocity)
            sounding.add(note)
        else:
            message = midi.NoteOffMessage(channel_id=CHANNEL, note_number=note, velocity=0)
            sounding.discard(note)
        out.send_message(message.serialize())
        print(event["time"], message)


def main():
    events = sorted(json.loads(SCORE.read_text()), key=lambda event: event["time"])
    out = open_output(PORT_NAME)
    sounding = set()  # notes that are on, so Ctrl+C can turn them off

    scheduler = Scheduler()
    rout = scheduler.sched(play(out, events, sounding))
    try:
        rout.result()  # wait here until the whole score has played
    except KeyboardInterrupt:
        print("Stopping.")
        rout.cancel()
    finally:
        # stop the Scheduler's event loop so its thread ends and the script can exit
        scheduler.loop.call_soon_threadsafe(scheduler.loop.stop)
        scheduler.thread.join()
        for note in sounding:
            out.send_message(midi.NoteOffMessage(channel_id=CHANNEL, note_number=note, velocity=0).serialize())
        out.close_port()


if __name__ == "__main__":
    main()
