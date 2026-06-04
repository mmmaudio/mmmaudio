"""Envelope generator module.

This module provides an envelope generator class that can create complex envelopes with multiple segments, curves, and looping capabilities.
"""

from mmm_audio import *

struct EnvParams(Movable, Copyable):
    """Parameters for the Env class.

    This struct defines the parameters of an envelope. An instance of
    this struct is used internally in the `Env` struct. It is also used
    in other places in the library when appropriate.
    """

    var values: List[Float64]
    var times: List[Float64]
    var curves: List[Float64]
    var loop: Bool
    var time_warp: Float64

    def __init__(out self, values: List[Float64] = [0,1,0], times: List[Float64] = [1,1], curves: List[Float64] = [1], loop: Bool = False, time_warp: Float64 = 1.0):
        """Initialize EnvParams.

        Args:
            values: List of envelope values at each breakpoint.
            times: List of durations (in seconds) for each segment between adjacent breakpoints. This List should be one element shorter than the `values` List.
            curves: List of curve shapes for each segment. Positive values for convex "exponential" curves, negative for concave "logarithmic" curves. (if the output of the envelope is negative, the curve will be inverted).
            loop: Bool to indicate if the envelope should loop.
            time_warp: Time warp factor to speed up or slow down the envelope. Default is 1.0 meaning no warp. A value of 2.0 will make the envelop take twice as long to complete. A value of 0.5 will make the envelope take half as long to complete.
        """
        
        self.values = values.copy()  # Make a copy to avoid external modifications
        self.times = times.copy()
        self.curves = curves.copy()
        self.loop = loop
        self.time_warp = time_warp

struct Env(Movable, Copyable):
    """Envelope generator with an arbitrary number of segments."""

    var sweep: Sweep[1]  # Sweep for tracking time
    var rising_bool_detector: RisingBoolDetector[1]  # Track the last trigger state
    var is_active: Bool  # Flag to indicate if the envelope is active
    var _times: List[Float64]  # List of segment durations - this is a private variable. Don't touch it.
    var dur: Float64  # Total duration of the envelope
    var freq: Float64  # Frequency multiplier for the envelope
    var trig_point: Float64  # Point at which the asr envelope was triggered
    var params: EnvParams
    var eoc: Bool
    var world: World

    def __init__(out self, world: World):
        """Initialize the Env2 struct - with internal params.

        Args:
            world: Pointer to the MMMWorld.
        """

        self.world = world
        self.sweep = Sweep(world)
        self.rising_bool_detector = RisingBoolDetector()  # Initialize rising bool detector
        self.is_active = False
        self._times = List[Float64]() 
        self.dur = 0.0  
        self.freq = 0.0
        self.trig_point = 0.0
        self.params = EnvParams()
        self.params.values=[0,1,0]
        self.params.times=[1,1]
        self.eoc = False
        self._reset_vals()

    @doc_hidden
    def _reset_vals(mut self):
        """Reset internal values."""

        if self._times.__len__() != (self.params.times.__len__() + 1):
            self._times.clear()
        while self._times.__len__() < (self.params.times.__len__() + 1):
            self._times.insert(0, 0.0)  # Ensure times list has the same length as the input times
        for i in range(self.params.times.__len__()):
            self._times[i+1] = self._times[i] + self.params.times[i]  # Copy values from input times

        self.dur = self._times[len(self._times) - 1]  # Set total duration to the last value in times
        if self.dur > 0.0:
            self.freq = 1.0 / self.dur
        else:
            self.freq = 0.0

    def next[win_type: WindowType = WindowType.none, interp: Interp = Interp.none](mut self, trig: Bool = True) -> Float64:
         """Generate the next envelope value. Uses the internal `params` struct for envelope parameters. See `EnvParams` for more details on the parameters. Uses an internal phasor to track the progression of the envelope, which is reset on each trigger.

        Parameters:
            win_type: Used to apply a window type to the envelope curves. Default is WindowType.none, which means linear ramps. See `WindowType` struct for available window types.
            interp: Interpolation type to apply to the window. Default is Interp.none, which means no interpolation. See `Interp` struct for available interpolation types.
        
        Args:
            trig: Trigger to start the envelope.
        
        Returns:
            The next envelope value.
        """
        phase = 0.0
        self.eoc = False
        if not self.is_active:
            if self.rising_bool_detector.next(trig):
                self.sweep.phase = 0.0  # Reset phase on trigger
                self.is_active = True  # Start the envelope
                self._reset_vals()
            else:
                return self.params.values[0]
        else:
            if self.rising_bool_detector.next(trig):
                self.sweep.phase = 0.0  # Reset phase on trigger
                self._reset_vals()
            else:    
                phase = self.sweep.next(self.freq / self.params.time_warp)

        if self.params.loop and phase >= 1.0:  # Check if the envelope has completed
            self.sweep.phase = 0.0  # Reset phase for looping
            phase = 0.0
            self.eoc = True
        elif not self.params.loop and phase >= 1.0:
            self.eoc = True
            if self.params.values[len(self.params.values) - 1] == self.params.values[0]:
                self.is_active = False  # Stop the envelope if not looping and last value is the same as first
                return self.params.values[0]  # Return the first value if not looping
            else:
                return self.params.values[len(self.params.values) - 1]  # Return the last value if not looping

        env = self._apply_phase(phase)
        comptime if win_type != WindowType.none:
            env *= win_read[win_type, interp](self.world, env*0.5)
        
        return env

    def next[win_type: WindowType = WindowType.none, interp: Interp = Interp.linear](mut self, trig: Bool, phase: MFloat[1]) -> MFloat[1]:
        """Generate the next envelope value with a provided phase rather than using the internal phasor. Works well with a Line UGen. Uses the internal `params` struct for envelope parameters. See `EnvParams` for more details on the parameters.

        Parameters:
            win_type: Used to apply a window type to the envelope curves. Default is WindowType.none, which means linear ramps. See `WindowType` struct for available window types.
            interp: Interpolation type to apply to the window. Default is Interp.linear. See `Interp` struct for available interpolation types.

        Args:
            trig: Trigger to start the envelope.
            phase: The current phase of the envelope, between 0 and 1. This allows the user to control the progression of the envelope externally rather than using the internal phasor.
        
        Returns:
            The envelope value at the specified phase.
        """
        if self.rising_bool_detector.next(trig):
            self._reset_vals()
        if phase >= 1.0:
            return self.params.values[self.params.values.__len__() - 1]
            
        env = self._apply_phase(phase)

        comptime if win_type != WindowType.none:
            env *= win_read[win_type, interp](self.world, env*0.5)
        
        return env

    @doc_hidden
    def _apply_phase(mut self, phase: MFloat[1]) -> MFloat[1]:
        var segment = 0
        phase2 = phase * self.dur
        while segment < len(self._times) - 1 and phase2 >= self._times[segment + 1]:
            segment += 1

        # by the above logic, segment should never be able to be the last index of times or values 
        out = lincurve(phase2, self._times[segment], self._times[segment + 1], self.params.values[segment], self.params.values[segment + 1], self.params.curves[segment % len(self.params.curves)])
        return out

    def get_phase(self) -> Float64:
        """Get the current phase of the envelope.

        Returns:
            The current envelope phase, clamped to the range 0 to 1.
        """
        return clip(self.sweep.phase, 0.0, 1.0)

    @staticmethod
    def get_env_buffer[num_chans: Int = 1, win_type: WindowType = WindowType.none, interp: Interp = Interp.linear](world: World, size: Int, *env_defs: EnvParams) -> SIMDBuffer[num_chans]:
        """Get a SIMDBuffer of envelope values.

        Parameters:
            num_chans: Number of SIMD channels in the output buffer.
            win_type: A WindowType to apply to the envelope. See [WindowType](MMMMAudio.md#struct-windowtype) struct for available window types.
            interp: Interpolation mode used when reading the window. See [Interp](MMMMAudio.md#struct-interp) struct for available interpolation types.

        Args:
            world: Pointer to the MMMWorld.
            size: Size of the output table.
            env_defs: One or more EnvParams structs defining the envelope parameters to generate the table from.

        Returns:
            A SIMDBuffer containing `num_chans` of envelope values.
        """
        env = Env(world)
        buffer = SIMDBuffer[num_chans].zeros(size)
        print(env_defs.__len__())
        for i in range(min(env_defs.__len__(), num_chans)):
            print(i)
            env.params = env_defs[i].copy()
            
            for j in range(size):
                phase = Float64(j) / Float64(size - 1)
                buffer.data[j][i] = env.next[win_type, interp](True, phase)
        return buffer^

def win_read[window_type: WindowType = WindowType.sine, interp: Interp = Interp.none](world: World, phase: MFloat[1]) -> MFloat[1]:
    """Reads a window function from MMMWorld's default Window by indexing into it with the provided phase.

    Parameters:
        window_type: The type of window to look up. See `WindowType` struct for available window types.
        interp: Interpolation type to apply to the window. Default is Interp.none, which means no interpolation. See `Interp` struct for available interpolation types.

    Args:
        world: Pointer to the MMMWorld.
        phase: The current phase of the window, between 0 and 1.

    Returns:
        The window value at the specified phase.
    """
    temp = world[].windows.value()
    val = temp[].at_phase[window_type=window_type, interp=interp](world, phase)
    return val

def buf_read[num_chans: Int, interp: Interp = Interp.linear, bWrap: Bool = True](world: World, env_buffer: SIMDBuffer[num_chans], phase: MFloat[1], prev_phase: MFloat[1] = 0.0) -> MFloat[num_chans]:
    """Reads a buffer by indexing into it with the provided phase.

    Parameters:
        num_chans: Number of SIMD channels stored in the buffer.
        interp: Interpolation mode used for buffer lookup. See [Interp](MMMMAudio.md#struct-interp) struct for available interpolation types.
        bWrap: Whether the read should wrap around the buffer edges.

    Args:
        world: Pointer to the MMMWorld.
        env_buffer: The buffer containing the envelope values.
        phase: The phase at which to read the buffer, between 0 and 1.
        prev_phase: The previous phase, used for sinc interpolation. Otherwise, this argument can be ignored.

    Returns:
        The envelope value at the specified phase.
    """
    comptime if interp == Interp.sinc:
        val = SpanInterpolator.read[interp=interp,bWrap=bWrap](
            world=world,
            data=env_buffer.data,
            f_idx=phase * Float64(len(env_buffer.data) - 1),
            prev_f_idx=prev_phase * Float64(len(env_buffer.data) - 1)
        )
    else:
         val = SpanInterpolator.read[interp=interp,bWrap=bWrap](
            world=world,
            data=env_buffer.data,
            f_idx=phase * Float64(len(env_buffer.data) - 1),
            prev_f_idx=0.0
        )
    return val

# min_env is just a function, not a struct
def min_env[win_type: WindowType = WindowType.none, interp: Interp = Interp.none](world: World, phase: MFloat[1] = 0.0, ramp_amount: MFloat[1] = 0.01) -> MFloat[1]:
    """Simple envelope.

    Envelope that creates a simple trapezoidal envelope with linear ramps. The attack and release ramps are determined by the `ramp_amount` parameter.

    Parameters:
        win_type: Used to apply a window type to the envelope curves. Default is WindowType.none, which means linear ramps. See `WindowType` struct for available window types.
        interp: Interpolation type to apply to the window. Default is Interp.none, which means no interpolation. See `Interp` struct for available interpolation types.

    Args:
        world: Pointer to the MMMWorld.
        phase: Current env position between 0 (beginning) and 1 (end).
        ramp_amount: Duration of the attack and release ramps as a proportion of the total envelope duration. Values between 0 and 0.5.

    Returns:
        Envelope value at the current ramp position.
    """
    r_a2 = clip(ramp_amount, 0.0, 0.5)
    if phase < r_a2:
        env = phase / r_a2
    elif phase > (1.0 - r_a2):
        env = (1.0 - phase) / r_a2
    else:
        env = 1.0

    comptime if win_type != WindowType.none:
        env *= win_read[win_type, interp](world, env/2.)

    return env

struct ASREnv(Movable, Copyable):
    """Simple ASR envelope generator."""
    var sweep: Sweep[1] 
    var bool_changed: Changed[Bool]  # To detect changes in the gate signal
    var freq: Float64 
    var is_active: Bool
    var eoc: Bool
    var eoc_rbd: RisingBoolDetector[1]
    var world: World

    def __init__(out self, world: World):
        """Initialize the ASREnv struct.
        
        Args:
            world: Pointer to the MMMWorld.
        """
        self.sweep = Sweep(world)
        self.bool_changed = Changed(False)  # Initialize with False
        self.freq = 0.0  
        self.is_active = False
        self.eoc = False  # End of Cycle flag
        self.eoc_rbd = RisingBoolDetector() 
        self.world = world

    def next[win_type: WindowType = WindowType.none, interp: Interp = Interp.none](mut self, attack: Float64, sustain: Float64, release: Float64, gate: Bool, curve: MFloat[2] = 1) -> Float64:
        """Simple ASR envelope generator.
        
        Parameters:
            win_type: Used to apply a window type to the envelope curves. Default is WindowType.none, which means linear ramps. See `WindowType` struct for available window types.
            interp: Interpolation type to apply to the window. Default is Interp.none. See `Interp` struct for available interpolation types.

        Args:
            attack: (Float64): Attack time in seconds.
            sustain: (Float64): Sustain level (0 to 1).
            release: (Float64): Release time in seconds.
            gate: (Bool): Gate signal (True or False).
            curve: (MFloat[2]): Can pass a Float64 for equivalent curve on rise and fall or MFloat[2] for different rise and fall curve. Positive values for convex "exponential" curves, negative for concave "logarithmic" curves.

        Returns:
            The current ASR envelope value.
        """

        if self.bool_changed.next(gate):
            if gate:
                self.is_active = True
                self.freq = 1.0 / attack
            else:
                self.freq = -1.0 / release

        _ = self.sweep.next(self.freq, gate)
        
        self.sweep.phase = clip(self.sweep.phase, 0.0, 1.0)
        self.is_active = self.sweep.phase > 0.0 or gate
        self.eoc = self.eoc_rbd.next(not self.is_active)

        if gate:
            ramp = lincurve(self.sweep.phase, 0.0, 1.0, 0.0, 1.0, curve[0])
        else:
            ramp = lincurve(self.sweep.phase, 0.0, 1.0, 0.0, 1.0, curve[1])

        comptime if win_type != WindowType.none:
            ramp *= win_read[win_type, interp](self.world, ramp*0.5)

        return ramp * sustain

struct Compressor[num_chans: Int](Movable, Copyable):
    """Compressor from Nathan Ho's [Negative Compression web post](https://nathan.ho.name/posts/negative-compression/).
    
    Params:
        num_chans: Number of channels of input/output.
    """

    var amp: Amplitude[Self.num_chans]
    var lag: LagUD[1]
    var denom: Float64
    var sidechain: MFloat[1]
    var changed: Changed[MFloat[1]]
    var changed2: Changed[MFloat[1]]

    def __init__(out self, world: World):
        """Initialize the Compressor struct.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.amp = Amplitude[Self.num_chans](world)
        self.lag = LagUD[1](world)
        self.denom = sqrt(Float64(Self.num_chans))
        self.sidechain = 1.0

        self.changed = Changed(0.01)
        self.changed2 = Changed(0.1)

        self.lag.set_lag_times(0.01, 0.1)
        self.amp.set_params(0.001, 0.01)
    
    def next(mut self, input: MFloat[Self.num_chans], threshold: MFloat[1] = -20.0, ratio: MFloat[1] = 4.0, attack: MFloat[1] = 0.01, release: MFloat[1] = 0.1, knee_width: MFloat[1] = 0.0) -> MFloat[Self.num_chans]:
        """Returns the compressed signal, which is the original signal multiplied by the negative compression gain.
        
        Args:
            input: MFloat[Self.num_chans] audio signal to be compressed.
            threshold: MFloat[1] threshold in dBFS above which compression occurs.
            ratio: MFloat[1] compression ratio. For example, a ratio of 4.0 means that for every 4 dB the input signal exceeds the threshold, the output will only exceed the threshold by 1 dB.
            attack: MFloat[1] attack time in seconds for the compressor's envelope follower.
            release: MFloat[1] release time in seconds for the compressor's envelope follower.
            knee_width: MFloat[1] width of the knee in dB. A value of 0 means a hard knee, while higher values create a softer knee N/2 decibels around the threshold.
        
        Returns:
            MFloat[Self.num_chans] compressed audio signal, which is the original signal multiplied by the negative compression gain.
        """

        return self.next_neg_comp(input, threshold, ratio, attack, release, knee_width) * input

    def next_neg_comp(mut self, input: MFloat[Self.num_chans], threshold: MFloat[1] = -20.0, ratio: MFloat[1] = 4.0, attack: MFloat[1] = 0.01, release: MFloat[1] = 0.1, knee_width: MFloat[1] = 0.0) -> MFloat[1]:
        """Returns the negative compression gain (in amplitude units, not dB) for the input signal, which can be multiplied with the original signal or used as a sidechain.
        
        Args:
            input: MFloat[Self.num_chans] audio signal to be compressed.
            threshold: MFloat[1] threshold in dBFS above which compression occurs.
            ratio: MFloat[1] compression ratio. For example, a ratio of 4.0 means that for every 4 dB the input signal exceeds the threshold, the output will only exceed the threshold by 1 dB.
            attack: MFloat[1] attack time in seconds for the compressor's envelope follower.
            release: MFloat[1] release time in seconds for the compressor's envelope follower.
            knee_width: MFloat[1] width of the knee in dB. A value of 0 means a hard knee, while higher values create a softer knee N/2 decibels around the threshold.

        Returns:
            MFloat[1] negative compression gain in amplitude units, which can be multiplied with the original signal or used as a sidechain.
        """

        ratio2 = max(ratio, 1.0)  # Ensure ratio is at least 1:1

        c1 = self.changed.next(attack)
        c2 = self.changed2.next(release)
        if c1 or c2:
            self.lag.set_lag_times(release, attack) # backwards because gain reduction is 1 when there is no gain reduction so the attack goes down and the release goes up

        amp = self.amp.next(input).reduce_add() / self.denom
        amp_db = ampdb(max(amp, dbamp(-100.0))) 
        val = amp_db - threshold

        if val <= -knee_width / 2:
            gain_reduction = 0.0
        elif val >= knee_width / 2:
            gain_reduction = val * (1.0 / ratio2 - 1)
        else:
            
            gain_reduction = (1.0 / ratio2 - 1) * (val + knee_width / 2) ** 2 / (2 * knee_width)
        self.sidechain = dbamp(self.lag.next(gain_reduction))

        return self.sidechain
    