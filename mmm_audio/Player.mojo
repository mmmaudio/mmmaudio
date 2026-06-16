from mmm_audio import *

# it is a bit gross to be overloading the functions like this. A Trait for Buffer and SIMDBuffer would be better, but that would need Traits with Parameters, because the Span passed into the get_sample function needs to know the number of channels at compile time for the type signature. 
struct Play(Movable, Copyable):
    """The principle buffer playback object for MMMAudio.
    
    Plays back audio from a Buffer with variable rate, interpolation, looping, and triggering capabilities.
    """
    var impulse: Phasor[1]  # Current phase of the buf
    var active: Bool
    var world: World
    var rising_bool_detector: RisingBoolDetector[1]
    var start_frame: Int 
    var reset_phase_point: Float64
    var phase_offset: Float64  # Offset for the phase calculation

    def __init__(out self, world: World):
        """Initialize the buffer playback object.
        
        Args:
            world: Pointer to the MMMWorld instance.
        """

        self.world = world
        self.impulse = Phasor(world)
        self.active = False
        self.rising_bool_detector = RisingBoolDetector()

        self.start_frame = 0
        self.reset_phase_point = 0.0
        self.phase_offset = 0.0

    def next[num_chans: Int = 1, interp: Interp = Interp.linear, bWrap: Bool = False](mut self, buf: SIMDBuffer[num_chans], rate: Float64 = 1, loop: Bool = True, trig: Bool = True, start_frame: Int = 0, var num_frames: Int = -1) -> MFloat[num_chans]: 
        """Get the next sample from a SIMD audio buf (SIMDBuffer). The internal phasor is advanced according to the specified rate. If a trigger is received, playback starts at the specified start_frame. If looping is enabled, playback will loop back to the start when reaching the end of the specified num_frames. A key difference between SIMDBuffer and Buffer is that calling next on a SIMDBuffer always returns the entire SIMD vector of samples for the current phase, whereas with Buffer, you can specify the number of channels to read.

        Parameters:
            num_chans: Number of output channels to read from the buffer and also the size of the output SIMD vector.
            interp: Interpolation method to use when reading from the buffer (see the Interp struct for available options - default: Interp.linear).
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). This is necessary when reading from a wavetable or other oscillating buffer, for instance, where the ending samples of the buffer connect seamlessly to the first. If this is false, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buf: The audio buf to read from (List[MFloat[num_chans]]).
            rate: The playback rate. 1 is the normal speed of the buf.
            loop: Whether to loop the buf (default: True).
            trig: Trigger starts the synth at start_frame (default: 1.0).
            start_frame: The start frame for playback (default: 0) upon receiving a trigger.
            num_frames: The end frame for playback (default: -1 means to the end of the buf).

        Returns:
            The next sample(s) from the buf as a SIMD vector.
        """

        # Check for Trigger and if so, Update Values
        # ==========================================
        if self.rising_bool_detector.next(trig) and buf.num_frames_f64 > 0.0:
            self.active = True
            self.start_frame = start_frame  # Set start frame
            self.phase_offset = Float64(self.start_frame) / buf.num_frames_f64
            if num_frames < 0:
                self.reset_phase_point = 1.0
            else:
                self.reset_phase_point = Float64(num_frames) / buf.num_frames_f64  
        
        if not self.active:
            return 0.0  # Return zeros if not active

        # Use Values to Calculate Frequency and Advance Phase
        # ===================================================
        freq = rate / buf.duration  # Calculate step size based on rate and sample rate
        # keep previous phase for sinc interp
        prev_phase = (self.impulse.phase + self.phase_offset) % 1.0
        # advance phase and get end rise trigger
        eor = self.impulse.next_bool(freq, trig = trig)
        if loop:
            # Wrap Phase
            if self.impulse.phase >= self.reset_phase_point:
                self.impulse.phase -= self.reset_phase_point
            return buf.at_phase[interp=interp, bWrap=bWrap](self.world, self.impulse.phase + self.phase_offset, prev_phase)
        else:
            # Not in Loop Mode
            if trig: eor = False
            phase = self.impulse.phase
            # [TODO] I feel like it might not be necessary to check *all* these?
            if phase >= 1.0 or phase < 0.0 or eor or phase >= self.reset_phase_point:
                self.active = False
                return 0.0
            else:
                return buf.at_phase[interp=interp, bWrap=bWrap](self.world, self.impulse.phase + self.phase_offset, prev_phase)
                
    @always_inline
    def next[num_chans: Int = 1, interp: Interp = Interp.linear, bWrap: Bool = False](mut self, buf: Buffer, rate: Float64 = 1, loop: Bool = True, trig: Bool = True, start_frame: Int = 0, var num_frames: Int = -1, start_chan: Int = 0) -> MFloat[num_chans]: 
        """Get the next sample from an audio buf (Buffer). The internal phasor is advanced according to the specified rate. If a trigger is received, playback starts at the specified start_frame. If looping is enabled, playback will loop back to the start when reaching the end of the specified num_frames.

        Parameters:
            num_chans: Number of output channels to read from the buffer and also the size of the output SIMD vector.
            interp: Interpolation method to use when reading from the buffer (see the Interp struct for available options - default: Interp.linear).
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). This is necessary when reading from a wavetable or other oscillating buffer, for instance, where the ending samples of the buffer connect seamlessly to the first. If this is false, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buf: The audio buf to read from (List[Float64]).
            rate: The playback rate. 1 is the normal speed of the buf.
            loop: Whether to loop the buf (default: True).
            trig: Trigger starts the synth at start_frame (default: 1.0).
            start_frame: The start frame for playback (default: 0) upon receiving a trigger.
            num_frames: The end frame for playback (default: -1 means to the end of the buf).
            start_chan: The start channel for multi-channel bufs (default: 0).

        Returns:
            The next sample(s) from the buf as a SIMD vector.
        """

        # Check for Trigger and if so, Update Values
        # ==========================================
        if self.rising_bool_detector.next(trig) and buf.num_frames_f64 > 0.0:
            self.active = True  # Set active flag on trigger
            self.start_frame = start_frame  # Set start frame
            self.phase_offset = Float64(self.start_frame) / buf.num_frames_f64
            if num_frames < 0:
                self.reset_phase_point = 1.0
            else:
                self.reset_phase_point = Float64(num_frames) / buf.num_frames_f64  
        
        if not self.active:
            return 0.0  # Return zeros if not active

        # Use Values to Calculate Frequency and Advance Phase
        # ===================================================
        freq = rate / buf.duration  # Calculate step size based on rate and sample rate
        prev_phase = (self.impulse.phase + self.phase_offset) % 1.0
        eor = self.impulse.next_bool(freq, trig = trig)
        if loop:
            # Wrap Phase
            if self.impulse.phase >= self.reset_phase_point:
                self.impulse.phase -= self.reset_phase_point
            return self.get_sample[num_chans,interp](buf, prev_phase, start_chan)
        else:
            # Not in Loop Mode
            if trig: eor = False
            phase = self.impulse.phase
            # [TODO] I feel like it might not be necessary to check *all* these?
            if phase >= 1.0 or phase < 0.0 or eor or phase >= self.reset_phase_point:
                self.active = False  # Set active flag to False if phase is out of bounds
                return 0.0
            else:
                return self.get_sample[num_chans,interp, bWrap](buf, prev_phase, start_chan)

    @doc_hidden
    @always_inline
    def get_sample[num_chans: Int, interp: Interp, bWrap: Bool = False](self, buf: Buffer, prev_phase: Float64, start_chan: Int) -> MFloat[num_chans]:
        
        out = MFloat[num_chans](0.0)
        comptime for out_chan in range(num_chans):
            out[out_chan] = buf.at_phase[interp=interp, bWrap=bWrap](self.world, start_chan + out_chan, self.impulse.phase + self.phase_offset, prev_phase)
        return out

    @always_inline
    def get_relative_phase(mut self) -> Float64:
        return self.impulse.phase / self.reset_phase_point

    def reset_phase(mut self):
        self.impulse.phase = 0.0
