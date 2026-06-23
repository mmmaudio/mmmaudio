import supriya_midi as s_m

# create the MidiIn object
in_port = s_m.MidiIn()

def callback(msg, timestamp, data=None):
    msg = s_m.MidiMessage.parse(msg)
    print(f"Received {msg=}")
    print(f"Message type: {type(msg)}")

in_port.set_callback(callback)

# find your midi devices
ports = s_m.list_ports()
port_num = ports.index('Oxygen Pro Mini USB MIDI')

if in_port.get_ports():
    in_port.open_port(port_num)
else:
    in_port.open_virtual_port("My virtual output")