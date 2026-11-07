"""Plays resources/bach2.json as MIDI note on, note off and filter cutoff (CC) messages out of the IAC Driver, using supriya_midi.
The events are played by a coroutine running on the MMMAudio Scheduler.

bach2.json is a list of events, each with a time in seconds, a key and a value:

    {"time": 1.908788, "message": "mmm_audio.send_ints", "key": "midi_note_on", "value": [1, 65, 72]}
    {"time": 2.005364, "message": "mmm_audio.send_ints", "key": "midi_note_off", "value": [1, 65, 0]}
    {"time": 0.01, "message": "mmm_audio.send_float", "key": "filter_cutoff", "value": 200.78}

Note values are [channel (from 1), note, velocity]. filter_cutoff is a frequency in Hz (200 - 10000), which is
sent as MIDI CC 33, mapped exponentially so CC 0 - 127 covers 20 - 20000 Hz. That is the controller and range
examples/MidiKeyboard.mojo uses for its filter cutoff, so it hears the same frequencies as are in the score.

This uses IAC Driver by default, but it can be any midi hardware/software that accepts MIDI output.

On macOS, turn the IAC Driver on in Audio MIDI Setup (Window > Show MIDI Studio, double-click IAC Driver, check "Device is online"). Then anything listening to "IAC Driver Bus 1", such as a DAW or examples/MidiKeyboard.py with its port changed to 'IAC Driver Bus 1', will play the notes.

Run it from the MMMAudio root: `pixi run python examples/MIDIToHardware.py`. Ctrl+C stops it and turns off any notes still sounding.
"""

import json
import math
import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_python package.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python.Scheduler import Scheduler
import supriya_midi as midi

SCORE = Path(__file__).resolve().parent.parent / "resources" / "bach2.json"
PORT_NAME = "IAC Driver"  # the first output port whose name contains this - change to whatever output you like
CHANNEL = 0  # MIDI channel 1 (supriya_midi counts channels from 0) - the channel the filter CC is sent on
CUTOFF_CC = 33  # the controller number the filter cutoff is sent on (MidiKeyboard reads its cutoff from CC 33)
CUTOFF_MIN, CUTOFF_MAX = 20.0, 20000.0  # the Hz range CC 0 - 127 covers - matches linexp(val, 0, 127, 20, 20000) in MidiKeyboard.mojo


def cutoff_to_cc(freq: float) -> int:
    """Map a cutoff frequency onto 0 - 127 exponentially, so equal CC steps are equal pitch steps."""
    freq = min(max(freq, CUTOFF_MIN), CUTOFF_MAX)
    return round(127 * math.log(freq / CUTOFF_MIN) / math.log(CUTOFF_MAX / CUTOFF_MIN))


def open_output(name: str) -> midi.MidiOut:
    out = midi.MidiOut()
    ports = out.get_ports()
    matches = [i for i, port in enumerate(ports) if name in port]
    if not matches:
        raise SystemExit(f"No MIDI output named '{name}'. The outputs are: {ports}")
    out.open_port(matches[0])
    print(f"Sending to {ports[matches[0]]}")
    return out


async def play(scheduler: Scheduler, out: midi.MidiOut, events: list, sounding: set):
    """Send each event when its time comes. Runs on the Scheduler's thread."""
    prev_time = 0.0
    prev_cc = None
    for event in events:
        # scheduler.wait times from when the previous event was due, so the timing doesn't drift
        await scheduler.wait(event["time"] - prev_time)
        prev_time = event["time"]

        key = event["key"]
        if key == "filter_cutoff":
            cc_value = cutoff_to_cc(event["value"])
            if cc_value == prev_cc:
                continue  # the cutoff changes every 10 ms, so skip repeats of the same CC value
            prev_cc = cc_value
            message = midi.ControllerChangeMessage(channel_id=CHANNEL, controller_number=CUTOFF_CC, controller_value=cc_value)
        elif key in ("midi_note_on", "midi_note_off"):
            channel, note, velocity = event["value"]
            channel_id = channel - 1  # bach2.json counts channels from 1
            if key == "midi_note_on" and velocity > 0:
                message = midi.NoteOnMessage(channel_id=channel_id, note_number=note, velocity=velocity)
                sounding.add((channel_id, note))
            else:
                message = midi.NoteOffMessage(channel_id=channel_id, note_number=note, velocity=0)
                sounding.discard((channel_id, note))
        else:
            continue
        out.send_message(message.serialize())
        if key != "filter_cutoff":
            print(event["time"], message)


def main():
    events = sorted(json.loads(SCORE.read_text()), key=lambda event: event["time"])
    out = open_output(PORT_NAME)
    sounding = set()  # notes that are on, so Ctrl+C can turn them off

    scheduler = Scheduler()
    rout = scheduler.sched(play(scheduler, out, events, sounding))
    try:
        rout.result()  # wait here until the whole score has played
    except KeyboardInterrupt:
        print("Stopping.")
        rout.cancel()
    finally:
        # stop the Scheduler's event loop so its thread ends and the script can exit
        scheduler.loop.call_soon_threadsafe(scheduler.loop.stop)
        scheduler.thread.join()
        for channel_id, note in sounding:
            out.send_message(midi.NoteOffMessage(channel_id=channel_id, note_number=note, velocity=0).serialize())
        out.close_port()


if __name__ == "__main__":
    main()
