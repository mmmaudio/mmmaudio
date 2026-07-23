from mmm_audio import *
from math import *

struct Euler[num_dims: Int](Copyable, Movable):
    """Simple Euler method ODE solver.

    Parameters:
        num_dims: Number of dimensions (state variables), e.g. 2 for position and velocity.
    """

    var state: InlineArray[Float64, Self.num_dims]
    var dt: Float64
    var world: World

    fn __init__(out self, world: World):
        """Initialize the Euler struct."""
        self.world = world
        self.dt = 1.0 / world[].sample_rate
        self.state = InlineArray[Float64, Self.num_dims](fill=Float64(0.0))

    fn step(mut self, derivatives: InlineArray[Float64, Self.num_dims]):
        """Perform a single Euler integration step.

        Args:
            derivatives: InlineArray of derivatives for each state variable.
        """
        for i in range(Self.num_dims):
            self.state[i] = self.state[i] + derivatives[i] * self.dt


struct RK2[num_dims: Int](Copyable, Movable):
    """Runge-Kutta 2nd order ODE solver.

    Parameters:
        num_dims: Number of dimensions (state variables), e.g. 2 for position and velocity.
    """

    var state: InlineArray[Float64, Self.num_dims]
    var dt: Float64
    var world: World

    fn __init__(out self, world: World):
        """Initialize the RK2 struct."""
        self.world = world
        self.dt = 1.0 / world[].sample_rate
        self.state = InlineArray[Float64, Self.num_dims](fill=Float64(0.0))

    fn step[fn_deriv: fn(InlineArray[Float64, Self.num_dims]) capturing -> InlineArray[Float64, Self.num_dims]](mut self):
        """Perform a single RK2 integration step.

        Args:
            fn_deriv: Function that computes derivatives given the current state.
        """
        var k1 = fn_deriv(self.state)
        var temp_state = InlineArray[Float64, Self.num_dims](fill=Float64(0.0))
        for i in range(Self.num_dims):
            temp_state[i] = self.state[i] + k1[i] * (self.dt / 2.0)

        var k2 = fn_deriv(temp_state)

        for i in range(Self.num_dims):
            self.state[i] = self.state[i] + k2[i] * self.dt


struct RK4[num_dims: Int](Copyable, Movable):
    """Runge-Kutta 4th order ODE solver.

    Parameters:
        num_dims: Number of dimensions (state variables), e.g. 2 for position and velocity.
    """

    var state: InlineArray[Float64, Self.num_dims]
    var dt: Float64
    var world: World

    fn __init__(out self, world: World):
        """Initialize the RK4 struct."""
        self.world = world
        self.dt = 1.0 / world[].sample_rate
        self.state = InlineArray[Float64, Self.num_dims](fill=Float64(0.0))

    fn step[fn_deriv: fn(InlineArray[Float64, Self.num_dims]) capturing -> InlineArray[Float64, Self.num_dims]](mut self):
        """Perform a single RK4 integration step.

        Args:
            fn_deriv: Function that computes derivatives given the current state.
        """
        var k1 = fn_deriv(self.state)
        var temp_state = InlineArray[Float64, Self.num_dims](fill=Float64(0.0))
        for i in range(Self.num_dims):
            temp_state[i] = self.state[i] + k1[i] * (self.dt / 2.0)

        var k2 = fn_deriv(temp_state)
        for i in range(Self.num_dims):
            temp_state[i] = self.state[i] + k2[i] * (self.dt / 2.0)

        var k3 = fn_deriv(temp_state)
        for i in range(Self.num_dims):
            temp_state[i] = self.state[i] + k3[i] * self.dt

        var k4 = fn_deriv(temp_state)
        for i in range(Self.num_dims):
            self.state[i] = self.state[i] + (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]) * (self.dt / 6.0)