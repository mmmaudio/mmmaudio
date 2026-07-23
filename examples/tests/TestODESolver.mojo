from mmm_audio import *
from math import *

# ── Oscillator (RK4) ─────────────────────────────────────────────────────────
# Tests that RK4 produces a clean sine wave via simple harmonic oscillator.
# dx/dt = v,  dv/dt = -omega^2 * x

struct TestODEOscillator(Representable, Movable, Copyable):
    var world: World
    var solver: RK4[2]
    var frequency: Float64
    var m: Messenger

    fn __init__(out self, world: World):
        self.world = world
        self.solver = RK4[2](world)
        self.frequency = 440.0
        self.m = Messenger(world)
        self.solver.state[0] = 1.0  # position
        self.solver.state[1] = 0.0  # velocity

    fn __repr__(self) -> String:
        return String("TestODEOscillator")

    fn next(mut self) -> SIMD[DType.float64, 2]:
        self.m.update(self.frequency, "frequency")
        var omega = 2.0 * pi * self.frequency
        var omega_sq = omega * omega

        @parameter
        fn derivatives(state: InlineArray[Float64, 2]) -> InlineArray[Float64, 2]:
            var derivs = InlineArray[Float64, 2](fill=Float64(0.0))
            derivs[0] = state[1]
            derivs[1] = -omega_sq * state[0]
            return derivs^

        self.solver.step[derivatives]()
        var output = self.solver.state[0]
        return SIMD[DType.float64, 2](output, output) * 0.5


# ── Filter (Euler) ───────────────────────────────────────────────────────────
# Tests that Euler solver produces a working RC lowpass filter.
# dV/dt = (Vin - Vout) / RC
# Mouse X controls cutoff: left channel sweeps 20Hz->20kHz, right sweeps inverse.

struct TestODEFilter(Representable, Movable, Copyable):
    var world: World
    var noise: WhiteNoise[2]
    var euler_l: Euler[1]
    var euler_r: Euler[1]

    fn __init__(out self, world: World):
        self.world = world
        self.noise = WhiteNoise[2]()
        self.euler_l = Euler[1](world)
        self.euler_r = Euler[1](world)

    fn __repr__(self) -> String:
        return String("TestODEFilter")

    fn next(mut self) -> SIMD[DType.float64, 2]:
        var input = self.noise.next()
        var freq_left = linexp(self.world[].mouse_x, 0.0, 1.0, 20.0, 20000.0)
        var freq_right = linexp(1.0 - self.world[].mouse_x, 0.0, 1.0, 20.0, 20000.0)
        var rc_l = 1.0 / (2.0 * pi * freq_left)
        var rc_r = 1.0 / (2.0 * pi * freq_right)

        var deriv_l = InlineArray[Float64, 1](fill=Float64(0.0))
        var deriv_r = InlineArray[Float64, 1](fill=Float64(0.0))
        deriv_l[0] = (input[0] - self.euler_l.state[0]) / rc_l
        deriv_r[0] = (input[1] - self.euler_r.state[0]) / rc_r
        self.euler_l.step(deriv_l)
        self.euler_r.step(deriv_r)

        return SIMD[DType.float64, 2](self.euler_l.state[0], self.euler_r.state[0]) * 0.5