# this example shows how to get both audio and knob inputs when exporting to vcv rack.
# MMMOsc4.py is its GUI: its sliders send freq1-4 in Hz (5 to 20000), shape1-4 from 0 to 1
# and fm1-4 from 0 to 1.
# the audio inputs come in through world[].sound_in():
#   inputs 0-3: FM of oscillators 1-4, each scaled by its own fm knob: at 1, +-5 V adds
#               +-2000 Hz (on a curve: +-2.5 V adds +-500 Hz); at 0 (the default) nothing
#   inputs 4-7: shape of oscillators 1-4, 0.1 per volt (10 V sweeps the whole range)

from mmm_audio import *

struct MMMOsc4(Movable, Copyable):
    var world: World
    var osc: Osc[4, Interp.sinc, TimesOversampling.x2]
    var freq_in1: Float64
    var freq_in2: Float64
    var freq_in3: Float64
    var freq_in4: Float64
    var shape_in1: Float64
    var shape_in2: Float64
    var shape_in3: Float64
    var shape_in4: Float64
    var fm_in1: Float64
    var fm_in2: Float64
    var fm_in3: Float64
    var fm_in4: Float64
    var lag: Lag[8]
    var fm_lag: Lag[4]
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[4, Interp.sinc, TimesOversampling.x2](world)

        # these are the knob inputs. they get values from the Messenger
        # (the same defaults as the sliders in MMMOsc4.py)
        self.freq_in1 = 110.0
        self.freq_in2 = 220.0
        self.freq_in3 = 330.0
        self.freq_in4 = 440.0
        self.shape_in1 = 0.0
        self.shape_in2 = 0.0
        self.shape_in3 = 0.0
        self.shape_in4 = 0.0
        self.fm_in1 = 0.0
        self.fm_in2 = 0.0
        self.fm_in3 = 0.0
        self.fm_in4 = 0.0
        self.lag = Lag[8](world, 0.05)
        self.fm_lag = Lag[4](world, 0.05)

        # the messenger is used to update the knob inputs from the external source
        self.m = Messenger(world)

    def next(mut self) -> MFloat[4]:
        # the knobs: freqs in Hz, shapes from 0 to 1
        self.m.update("freq1", self.freq_in1)
        self.m.update("freq2", self.freq_in2)
        self.m.update("freq3", self.freq_in3)
        self.m.update("freq4", self.freq_in4)
        self.m.update("shape1", self.shape_in1)
        self.m.update("shape2", self.shape_in2)
        self.m.update("shape3", self.shape_in3)
        self.m.update("shape4", self.shape_in4)
        self.m.update("fm1", self.fm_in1)
        self.m.update("fm2", self.fm_in2)
        self.m.update("fm3", self.fm_in3)
        self.m.update("fm4", self.fm_in4)

        # smooth the knob values, which only change once per block
        var lag_values = self.lag.next(MFloat[8](
            self.freq_in1, self.freq_in2, self.freq_in3, self.freq_in4,
            self.shape_in1, self.shape_in2, self.shape_in3, self.shape_in4
        ))
        var knob_freqs = lag_values.slice[4]()
        var knob_shapes = lag_values.slice[4, offset=4]()
        var fm = self.fm_lag.next(MFloat[4](self.fm_in1, self.fm_in2, self.fm_in3, self.fm_in4))

        # grab the audio inputs. reading past the last input channel would crash,
        # so the missing ones stay at 0 (running in Python, a stereo interface has only 2)
        var ins = MFloat[8](0.0)
        for i in range(min(8, self.world[].num_in_chans())):
            ins[i] = self.world[].sound_in(i)
            
        # each fm knob attenuates its freq input
        var freq_ins_audio = ins.slice[4]() 
        var shape_ins_audio = ins.slice[4, offset=4]()

        # 0 at an input leaves the knob's value as it is
        var f = knob_freqs + (2000.0 * fm * freq_ins_audio * abs(freq_ins_audio))
        var s = clip(knob_shapes + 0.5 * shape_ins_audio, 0.0, 1.0)

        var out = self.osc.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](
            f, osc_frac=s
        )

        return out
