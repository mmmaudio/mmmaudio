from mmm_audio import *
from math import *

# ── Van der Pol Oscillator (RK4) ────────────────────────────────────────────
# A classic nonlinear oscillator governed by:
#   dx/dt = v * omega
#   dv/dt = (mu * (1 - x^2) * v - x) * omega
#
# Scaling by omega keeps the oscillator normalized at unit amplitude regardless
# of frequency, and ensures RK4 remains stable at audio rate. When mu = 0 this
# reduces to a simple harmonic oscillator (pure sine). As mu increases the
# waveform distorts into the characteristic Van der Pol limit cycle shape.

struct VanDerPol(Representable, Movable, Copyable):
    var world: World
    var solver: RK4[2]
    var frequency: Float64
    var mu: Float64
    var gain: Float64
    var m_frequency: Messenger
    var m_mu: Messenger
    var m_gain: Messenger

    fn __init__(out self, world: World):
        self.world = world
        self.solver = RK4[2](world)
        self.frequency = 440.0
        self.mu = 1.0
        self.gain = 0.5
        self.m_frequency = Messenger(world)
        self.m_mu = Messenger(world)
        self.m_gain = Messenger(world)
        self.solver.state[0] = 2.0  # position (x), perturbed from equilibrium
        self.solver.state[1] = 0.0  # velocity (v)

    fn __repr__(self) -> String:
        return String("VanDerPol")

    fn next(mut self) -> SIMD[DType.float64, 2]:
        self.m_frequency.update(self.frequency, "frequency")
        self.m_mu.update(self.mu, "mu")
        self.m_gain.update(self.gain, "gain")

        var omega = 2.0 * pi * self.frequency
        var mu = self.mu
        var gain = self.gain

        @parameter
        fn derivatives(state: InlineArray[Float64, 2]) -> InlineArray[Float64, 2]:
            var derivs = InlineArray[Float64, 2](fill=Float64(0.0))
            derivs[0] = state[1] * omega
            derivs[1] = (mu * (1.0 - state[0] * state[0]) * state[1] - state[0]) * omega
            return derivs^

        self.solver.step[derivatives]()

        # Limit cycle amplitude ≈ 2.0; scale to [-0.5, 0.5] then apply gain
        var output = self.solver.state[0] * 0.5 * gain
        return SIMD[DType.float64, 2](output, output)
