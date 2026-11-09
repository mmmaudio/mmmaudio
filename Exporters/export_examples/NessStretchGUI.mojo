# NessStretchGUI wraps examples/NessStretch.mojo for exporting. NessStretchGUI.py is its GUI,
# with a slider for dur_mult and a button that picks a file to stretch.
#
# NessStretch reads "dur_mult" itself. The file comes in as "file" rather than NessStretch's
# own "file_name", so it can be checked here first: only a .wav that loads replaces the
# file that is playing.

from mmm_audio import *
from examples.NessStretch import NessStretch

struct NessStretchGUI(Movable, Copyable):
    var world: World
    var ness: NessStretch
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.ness = NessStretch(world)
        self.m = Messenger(world)

    def next(mut self) -> MFloat[2]:
        var file_name = String("")
        if self.m.notify_update("file", file_name):
            if file_name.lower().endswith(".wav"):
                var buffer = SIMDBuffer.load(file_name)
                # a file that fails to load comes back empty: keep the current one
                if buffer.num_frames > 0:
                    self.ness.buffer = buffer^
                    self.ness.file_name = file_name
                    # start the new file from the beginning
                    self.ness.phasor.phase = 0.0
                else:
                    print("NessStretchGUI: couldn't load", file_name)
            else:
                print("NessStretchGUI: not a .wav file:", file_name)

        return self.ness.next()
