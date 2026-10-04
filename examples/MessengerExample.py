"""
This example demonstrates the Messenger functionality in MMM-Audio, and the many kinds of messages that can be sent to control parameters in the audio graph.

We are able to send:
- Boolean values - .send_bool()
- Float values - .send_float()
- Lists of floats - .send_floats()
- Integer values - .send_int()
- Lists of integers - .send_ints()
- String values - .send_string() 
- Lists of strings - .send_strings()
- Trigger messages - .send_trig()

"""

from mmm_python import *

a = MMMAudio(128, graph_name="MessengerExample", package_name="examples")

a.start_audio()

a.send_bool("bool",True)
a.send_bool("bool",False)

a.send_float("float", 440.0)
a.send_float("float", 880.0)

a.send_floats("floats", [440.0, 550.0, 660.0])
a.send_floats("floats", [880.0, 990.0, 1100.0])

a.send_int("int", 42)
a.send_int("int", 84)

a.send_ints("ints", [1, 22, 3, 4, 5])
a.send_ints("ints", [5, 4, 3, 2, 1])
a.send_ints("ints", [100,200])

a.send_string("string", "Hello, World!")
a.send_string("string", "Goodbye, World!")

a.send_strings("strings", ["hello", "there", "general", "kenobi"])
a.send_strings("strings", ["goodbye", "there", "general", "grievous"])

a.send_trig("trig")

a.send_bool("tone_0.gate",True)
a.send_bool("tone_1.gate",True)
a.send_float("tone_0.freq",440 * 1.059)
a.send_float("tone_1.freq",midicps(74))
a.send_bool("tone_0.gate",False)
a.send_bool("tone_1.gate",False)


# A callback function can also be used for complex message handling (such as appending values to a list).
a.send_floats("callback", [1.0, 2.0, 3.0])

a.stop_audio()