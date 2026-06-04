from mmm_audio import *

from std.sys import simd_width_of

comptime model_out_size = 16  # Define the output size of the model

# THE SYNTH - is imported from TorchSynth.mojo in this directory
struct TorchSynth(Movable, Copyable):
    var world: World  # Pointer to the MMMWorld instance
    var osc1: Osc[1, Interp.sinc, TimesOversampling.x2]  # Oscillator 1 with interpolation and oversampling
    var osc2: Osc[1, Interp.sinc, TimesOversampling.x2]  # Oscillator 2 with interpolation and oversampling

    var model: MLP[2, model_out_size]  # Instance of the MLP model - 2 inputs, model_out_size outputs
    var lags: Lags[model_out_size]  # A Lags (Lags processed in parallel) for smoothing the model outputs

    var fb: Float64

    var latch1: Latch[]
    var latch2: Latch[]
    var impulse1: Phasor[]
    var impulse2: Phasor[]

    var filt1: SVF[]
    var filt2: SVF[]

    var dc1: DCTrap[]
    var dc2: DCTrap[]

    def __init__(out self, world: World):
        self.world = world
        self.osc1 = Osc[1, Interp.sinc, TimesOversampling.x2](self.world)
        self.osc2 = Osc[1, Interp.sinc, TimesOversampling.x2](self.world)

        # load the trained model
        self.model = MLP(self.world,"examples/nn_trainings/model_traced.pt", "mlp1", trig_rate=25.0)

        # Lags is a utility for processing multiple lag lines in parallel
        self.lags = Lags[model_out_size](self.world, 1/25.0)  # Assuming the model updates at 25 Hz

        # create a feedback variable so each of the oscillators can feedback on each sample
        self.fb = 0.0

        self.latch1 = Latch()
        self.latch2 = Latch()
        self.impulse1 = Phasor(self.world)
        self.impulse2 = Phasor(self.world)
        self.filt1 = SVF(self.world)
        self.filt2 = SVF(self.world)
        self.dc1 = DCTrap(self.world)
        self.dc2 = DCTrap(self.world)

    @always_inline
    def next(mut self) -> MFloat[2]:
        self.model.model_input[0] = self.world[].mouse_x
        self.model.model_input[1] = self.world[].mouse_y

        self.model.next()  # Run the model inference

        self.lags.next(self.model.model_output)  # Get the lagged outputs for smoother control

        # uncomment to see the output of the model
        # self.world[].print(self.lags[0], self.lags[1], self.lags[2], self.lags[3], self.lags[4], self.lags[5], self.lags[6], self.lags[7], self.lags[8], self.lags[9], self.lags[10], self.lags[11], self.lags[12], self.lags[13], self.lags[14], self.lags[15])

        # oscillator 1 -----------------------

        var freq1 = linexp(self.lags[0], 0.0, 1.0, 1.0, 3000) + (linlin(self.lags[1], 0.0, 1.0, 2.0, 5000.0) * self.fb)

        # next_interp implements a variable wavetable oscillator between the N provided wave types
        # in this case, we are using 0, 4, 5, 6 - Sine, BandLimited Tri, BL Saw, BL Square
        osc_frac1 = linlin(self.lags[3], 0.0, 1.0, 0.0, 1.0)
        osc1 = self.osc1.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](freq1, 0.0, False, osc_frac=osc_frac1)

        # samplerate reduction
        osc1 = self.latch1.next(osc1, self.impulse1.next_bool(linexp(self.lags[4], 0.0, 1.0, 100.0, self.world[].sample_rate*0.5)))
        osc1 = self.filt1.lpf(osc1, linexp(self.lags[5], 0.0, 1.0, 100.0, 20000.0), linlin(self.lags[6], 0.0, 1.0, 0.707, 4.0))

        tanh_gain = linlin(self.lags[7], 0.0, 1.0, 0.5, 10.0)

        # get rid of dc offset
        osc1 = tanh(osc1*tanh_gain)
        osc1 = self.dc1.next(osc1)

        # oscillator 2 -----------------------

        var freq2 = linlin(self.lags[8], 0.0, 1.0, 2.0, 5000.0) + (linlin(self.lags[9], 0.0, 1.0, 2.0, 5000.0) * osc1)

        osc_frac2 = linlin(self.lags[11], 0.0, 1.0, 0.0, 1.0)
        var osc2 = self.osc2.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](freq2, 0.0, False, osc_frac=osc_frac2)

        osc2 = self.latch2.next(osc2, self.impulse2.next_bool(linexp(self.lags[12], 0.0, 1.0, 100.0, self.world[].sample_rate*0.5)))

        osc2 = self.filt2.lpf(osc2, linexp(self.lags[13], 0.0, 1.0, 100.0, 20000.0), linlin(self.lags[14], 0.0, 1.0, 0.707, 4.0))

        tanh_gain = linlin(self.lags[15], 0.0, 1.0, 0.5, 10.0)
        osc2 = tanh(osc2*tanh_gain)
        osc2 = self.dc2.next(osc2)
        self.fb = osc2

        return MFloat[2](osc1, osc2) * 0.1


# THE GRAPH

struct TorchMlp(Movable, Copyable):
    var world: World
    var torch_synth: TorchSynth  # Instance of the TorchSynth

    def __init__(out self, world: World):
        self.world = world

        self.torch_synth = TorchSynth(self.world)  # Initialize the TorchSynth with the world instance

    def next(mut self) -> MFloat[2]:
        return self.torch_synth.next()