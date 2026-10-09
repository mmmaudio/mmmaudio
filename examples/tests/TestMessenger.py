"""Sends one message of every type `Messenger` supports. TestMessenger.mojo prints what each `update`, `notify_update` and `address_callback` receives."""

from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="TestMessenger", package_name="examples.tests")
mmm_audio.start_audio()

# update / notify_update
mmm_audio.send_float("f", 440.0)
mmm_audio.send_int("i", 7)
mmm_audio.send_bool("b", True)
mmm_audio.send_string("s", "hello")
mmm_audio.send_floats("fs", [1.5, 2.5])
mmm_audio.send_ints("is", [1, 2, 3])
mmm_audio.send_bools("bs", [True, False])
mmm_audio.send_strings("ss", ["a", "b"])
mmm_audio.send_floats("stereo", [0.25, 0.75])
mmm_audio.send_floats("quad", [1.0, 2.0])  # only the first 2 of 4 lanes change
mmm_audio.send_floats("f32", [3.5])
mmm_audio.send_trig("report")

# address_callback / notify_address_callback
mmm_audio.send_float("cb_float", 440.0)
mmm_audio.send_int("cb_int", 7)
mmm_audio.send_bool("cb_bool", True)
mmm_audio.send_string("cb_string", "hello")
mmm_audio.send_floats("cb_floats", [1.5, 2.5])
mmm_audio.send_ints("cb_ints", [1, 2, 3])
mmm_audio.send_bools("cb_bools", [True, False])
mmm_audio.send_strings("cb_strings", ["a", "b"])

mmm_audio.stop_audio()
