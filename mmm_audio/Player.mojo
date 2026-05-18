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
        """ 
        
        Args:
            world: pointer to the MMMWorld instance.
        """

        self.world = world
        self.impulse = Phasor(world)
        self.active = False
        self.rising_bool_detector = RisingBoolDetector()

        self.start_frame = 0
        self.reset_phase_point = 0.0
        self.phase_offset = 0.0

    def next[num_chans: Int = 1, interp: Int = Interp.linear, bWrap: Bool = False](mut self, buf: SIMDBuffer[num_chans], rate: Float64 = 1, loop: Bool = True, trig: Bool = True, start_frame: Int = 0, var num_frames: Int = -1) -> MFloat[num_chans]: 
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
            return self.get_sample[num_chans,interp](buf, prev_phase)
        else:
            # Not in Loop Mode
            if trig: eor = False
            phase = self.impulse.phase
            # [TODO] I feel like it might not be necessary to check *all* these?
            if phase >= 1.0 or phase < 0.0 or eor or phase >= self.reset_phase_point:
                self.active = False
                return 0.0
            else:
                return self.get_sample[num_chans,interp, bWrap](buf, prev_phase)

    @doc_hidden
    @always_inline
    def get_sample[num_chans: Int, interp: Int, bWrap: Bool = False](self, buf: SIMDBuffer[num_chans], prev_phase: Float64) -> MFloat[num_chans]:
        f_idx = ((self.impulse.phase + self.phase_offset)) * buf.num_frames_f64
        out = SpanInterpolator.read[num_chans, interp=interp,bWrap=bWrap](
                world=self.world,
                data=buf.data, 
                f_idx=f_idx,
                prev_f_idx=prev_phase * buf.num_frames_f64
            )
        return out

    @always_inline
    def next[num_chans: Int = 1, interp: Int = Interp.linear, bWrap: Bool = False](mut self, buf: Buffer, rate: Float64 = 1, loop: Bool = True, trig: Bool = True, start_frame: Int = 0, var num_frames: Int = -1, start_chan: Int = 0) -> MFloat[num_chans]: 
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
    def get_sample[num_chans: Int, interp: Int, bWrap: Bool = False](self, buf: Buffer, prev_phase: Float64, start_chan: Int) -> MFloat[num_chans]:
        
        out = MFloat[num_chans](0.0)
        comptime for out_chan in range(num_chans):
            out[out_chan] = SpanInterpolator.read[interp=interp,bWrap=bWrap](
                world=self.world,
                data=buf.data[(out_chan + start_chan) % len(buf.data)], # wrap around channels
                # f_idx=((self.impulse.phase + self.phase_offset) % 1.0) * buf.num_frames_f64,
                f_idx=((self.impulse.phase + self.phase_offset)) * buf.num_frames_f64, #no wrapping here
                prev_f_idx=prev_phase * buf.num_frames_f64
            )
        return out

    @always_inline
    def get_relative_phase(mut self) -> Float64:
        return self.impulse.phase / self.reset_phase_point

    def reset_phase(mut self):
        self.impulse.phase = 0.0


struct Grain(PolyObject):
    """A single grain for granular synthesis.

    Used as part of the TGrains and the PitchShift structs for triggered granular synthesis.
    """
    var world: World  # Pointer to the MMMWorld instance

    var start_frame: Int
    var num_frames: Int  
    var rate: Float64  
    var pan: Float64  
    var gain: Float64 
    var rising_bool_detector: RisingBoolDetector[1]
    var play_buf: Play
    var trigger: Bool
    var user_defined_env: Env
    var env_trigger: Bool

    # These are the functions that need to be implemented for the PolyObject trait:
    def check_active(mut self) -> Bool:
        return self.play_buf.active

    def set_trigger(mut self, trigger: Bool):
        self.trigger = trigger
    # ------------------------------------------------

    def __init__(out self, world: World):
        """

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world  
        self.start_frame = 0
        self.num_frames = 0
        self.rate = 1.0
        self.pan = 0.5 
        self.gain = 1.0
        self.rising_bool_detector = RisingBoolDetector() 
        self.play_buf = Play(world)
        self.trigger = False
        self.user_defined_env = Env(world)
        self.env_trigger = False

    @always_inline
    def next_pan2[num_playback_chans: Int = 1, win_type: Int = 0, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer,
    rate: Float64 = 1.0, 
    loop: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0, 
    pan: Float64 = 0.0, 
    gain: Float64 = 1.0,
    start_chan: Int = 0
    ) -> MFloat[2]:
        """Generate the next grain and pan it to stereo using pan2. Depending on num_playback_chans, will either pan a mono signal out 2 channels using pan2 or a stereo signal out 2 channels using pan_stereo.

        Parameters:
            num_playback_chans: Either 1 or 2, depending on whether you want to pan 1 channel of a buffer out 2 channels or 2 channels of the buffer with equal power panning.
            win_type: Type of window to apply to the grain (default is Hann window (WinType.hann)).
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grain (1.0 = normal speed).
            loop: Whether to loop the grain (default: False).
            start_frame: Starting frame position in the buffer.
            duration: Duration of the grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right).
            gain: Amplitude scaling factor for the grain.
            start_chan: The first buffer channel to read from for the grain (default: 0). If num_playback_chans is 2, the grain will read from start_chan and start_chan+1 for the left and right channels, respectively.
        """
        
        var sample = self.next[win_type=win_type, bWrap=bWrap](buffer, rate, loop, start_frame, duration, pan, gain)

        comptime if num_playback_chans == 1:
            panned = pan2(sample[start_chan], self.pan)
            return panned
        else:
            panned = pan_stereo(MFloat[2](sample[start_chan], sample[(start_chan + 1) % buffer.get_num_chans()]), self.pan) 
            return panned  # Return the output samples

    @always_inline
    def next_pan_az[num_simd_chans: Int = 4, win_type: Int = WindowType.hann, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer, 
    rate: Float64 = 1.0, 
    loop: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0, 
    pan: Float64 = 0.0, 
    gain: Float64 = 1.0, 
    num_speakers: Int = 4,
    buffer_chan: Int = 0, ) -> MFloat[num_simd_chans]:
        """Generate the next grain and pan it to N speakers using azimuth panning.

        Parameters:
            num_simd_chans: Number of output channels (speakers). Must be a power of two that is at least as large as num_speakers.
            win_type: Type of window to apply to the grain (default is Hann window (WindowType.hann) See [WindowType](MMMWorld.md/#struct-windowtype) for all options.).
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grain (1.0 = normal speed).
            loop: Whether to loop the grain (default: False).
            start_frame: Starting frame position in the buffer.
            duration: Duration of the grain in seconds.
            pan: Panning position from 0.0 to 1.0.
            gain: Amplitude scaling factor for the grain.
            num_speakers: Number of speakers to pan to.
            buffer_chan: The buffer channel to read from for the grain (default: 0).
        """
        
        var sample = self.next[win_type=win_type, bWrap=bWrap](buffer, rate, loop, start_frame, duration, pan, gain)

        panned = pan_az[num_simd_chans](sample[buffer_chan], self.pan, num_speakers) 

        return panned

    def next[num_chans: Int = 1, win_type: Int = WindowType.hann, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer[num_chans], 
    rate: Float64 = 1.0, 
    loop: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0,
    pan: Float64 = 0.0,
    gain: Float64 = 1.0) -> MFloat[num_chans]:
        """Generate the next unpanned grain. This is called internally by the panning functions, but can also be used directly if panning is not needed. The grain will always have the channel size of the SIMDBuffer.

        Parameters:
            num_chans: Number of output channels to read from the buffer and also the size of the output SIMD vector.
            win_type: Type of window to apply to the grain (default is Hann window (WinType.hann)).
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grain (1.0 = normal speed).
            loop: Whether to loop the grain (default: False).
            start_frame: Starting frame position in the buffer.
            duration: Duration of the grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right). This is not applied in this function, but is used by the panning functions that call this function.
            gain: Amplitude scaling factor for the grain.
        """
        trig2 = False
        if self.rising_bool_detector.next(self.trigger):
            self.start_frame = start_frame
            self.num_frames =  Int(duration * buffer.sample_rate*rate)  # Calculate end frame based on duration
            self.rate = rate
            self.gain = gain
            self.pan = pan
            trig2 = True
        
        # Get samples from Play with a new trigger
        sample = self.play_buf.next[interp=Interp.linear, bWrap=bWrap](buffer, self.rate, loop, trig2, self.start_frame, self.num_frames) 

        # Get the current phase of the PlayBuf
        if self.play_buf.reset_phase_point > 0.0:
            win_phase = self.play_buf.impulse.phase / self.play_buf.reset_phase_point  
        else:
            win_phase = 0.0  # Use the phase

        comptime if win_type == WindowType.user_defined:
            win = self.user_defined_env.next(trig2, win_phase)
        else:
            win = win_env[win_type, Interp.linear](self.world, win_phase)
        # this only works with 1 or 2 channels, if you try to do more, it will just return 2 channels
        sample = sample * win * self.gain  # Apply the window to the sample
        
        return sample
        

struct TGrains(Movable, Copyable):
    """
    Triggered granular synthesis. Each trigger starts a new grain.
    """
    var grains: List[Grain] 
    var trig: Bool
    var world: World
    var poly: PolyTriggerSig
    var env_params: EnvParams

    def __init__(out self, num_grains: Int, max_grains: Int, world: World):
        """

        Args:
            num_grains: Number of grains to initialize.
            max_grains: Maximum number of grains that can be allocated.
            world: Pointer to the MMMWorld instance.
        """
        self.world = world  
        self.grains = List[Grain]() 
        for _ in range(num_grains):
            self.grains.append(Grain(world)) 
        self.trig = False  
        self.poly = PolyTriggerSig(num_grains, max_grains)  
        self.env_params = EnvParams()  # Initialize with default parameters

    def set_env_params(mut self, env_params: EnvParams):
        """Set a the EnvParams of a user-defined envelope for all grains. This allows you to use a custom envelope shape instead of the built-in window types. Will update each grain on its next trigger. (Setting the EnvParams directly will not work).
        
        Args:
            env_params: An EnvParams object that defines the envelope shape.
        """
        self.env_params = env_params.copy()
        # set all the grains to update their user_defined_env with the new env on the next trigger
        for ref grain in self.grains:
            grain.env_trigger = True

    @doc_hidden
    def _trig_grain[win_type: Int](mut self, trig: Bool):
        comptime if win_type == WindowType.user_defined:            
            grain_num = self.poly.next(self.grains, trig)
            if grain_num >= 0:
                if self.grains[grain_num].env_trigger and trig:
                    self.grains[grain_num].user_defined_env.params = self.env_params.copy()
                    self.grains[grain_num].env_trigger = False
        else:
            _ = self.poly.next(self.grains, trig)

    @always_inline
    def next[num_playback_chans: Int = 1, win_type: Int = WindowType.hann, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer,
    rate: Float64 = 1.0, 
    trig: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.1,
    pan: Float64 = 0.0, 
    gain: Float64 = 1.0,
    buf_chan: Int = 0) -> MFloat[2]:
        """Generate the next set of grains. Uses pan2 to pan to 2 channels. Depending on num_playback_chans, will either pan a mono signal out 2 channels or a stereo signal out 2 channels.
        
        Parameters:
            num_playback_chans: Either 1 or 2, depending on whether you want to pan 1 channel of a buffer out 2 channels or 2 channels of the buffer with equal power panning.
            win_type: Type of window to apply to each grain (default is Hann window (WinType.hann)). For a user-defined envelope, set win_type to WindowType.user_defined and use the set_env_params function to assign EnvParams to all grains.
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:.
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grains (1.0 = normal speed).
            trig: Trigger signal (>0 to start a new grain).
            start_frame: Starting frame position in the buffer.
            duration: Duration of each grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right).
            gain: Amplitude scaling factor for the grains.
            buf_chan: The first buffer channel to read from for the grain (default: 0).

        Returns:
            List of output samples for all channels.
        """
        self._trig_grain[win_type](trig)

        out = MFloat[2](0.0, 0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                out += self.grains[i].next_pan2[num_playback_chans, win_type, bWrap=bWrap](buffer, rate, False, start_frame, duration, pan, gain, buf_chan)

        return out

    @always_inline
    def next_pan_az[num_simd_chans: Int = 2, win_type: Int = WindowType.hann, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer, 
    rate: Float64 = 1.0, 
    trig: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.1,
    pan: Float64 = 0.0, 
    gain: Float64 = 1.0, 
    num_speakers: Int = 2,
    buf_chan: Int = 0) -> MFloat[num_simd_chans]:
        """Generate the next set of grains. Uses azimuth panning for N channel output of a 1 channel grain.

        Parameters:
            num_simd_chans: The size of the output SIMD vector. Must be a power of two that is at least as large as num_speakers.
            win_type: Type of window to apply to each grain (default is Hann window (WinType.hann)). For a user-defined envelope, set win_type to WindowType.user_defined and use the set_env_params function to assign EnvParams to all grains.
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.
        
        Args:
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grains (1.0 = normal speed).
            trig: Trigger signal (>0 to start a new grain).
            start_frame: Starting frame position in the buffer.
            duration: Duration of each grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right).
            gain: Amplitude scaling factor for the grains.
            num_speakers: Number of speakers to pan to. Must be fewer than or equal to num_simd_chans.
            buf_chan: Channel in the buffer to read from.

        Returns:
            Output samples for all channels as a SIMD vector.
        """
            
        self._trig_grain[win_type](trig)

        out = MFloat[num_simd_chans](0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]:  # Only process grains that are active
                out += self.grains[i].next_pan_az[num_simd_chans, win_type, bWrap=bWrap](buffer, rate, False, start_frame, duration, pan, gain, num_speakers, buf_chan)

        return out

    @always_inline
    def next_all_chans[num_chans: Int, win_type: Int = WindowType.hann, bWrap: Bool = False](mut self, 
    mut buffer: SIMDBuffer[num_chans], 
    rate: Float64 = 1.0, 
    trig: Bool = False, 
    start_frame: Int = 0, 
    duration: Float64 = 0.1,
    gain: Float64 = 1.0) -> MFloat[num_chans]:
        """Generate the next set of grains. Returns all channels of the buffer with no panning as a num_chans sized SIMD vector.
        
        Parameters:
            num_chans: An inferred parameter based on the size of the input buffer.
            win_type: Type of window to apply to each grain (default is Hann window (WinType.hann)). For a user-defined envelope, set win_type to WindowType.user_defined and use the set_env_params function to assign EnvParams to all grains.
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            rate: Playback rate of the grains (1.0 = normal speed).
            trig: Trigger signal (>0 to start a new grain).
            start_frame: Starting frame position in the buffer.
            duration: Duration of each grain in seconds.
            gain: Amplitude scaling factor for the grains.

        Returns:
            List of output samples for all channels.
        """
        self._trig_grain[win_type](trig)

        out = MFloat[num_chans](0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                out += self.grains[i].next[num_chans, win_type, bWrap=bWrap](buffer, rate, False, start_frame, duration, gain)

        return out
    
    def reset(mut self):
        for ref grain in self.grains:
            grain.play_buf.active = False


struct PitchShift[num_chans: Int = 1, win_type: Int = WindowType.hann](Movable, Copyable):
    """
    An N channel granular pitchshifter. Each channel is processed in parallel.

    Parameters:
        num_chans: Number of input/output channels.
        win_type: Type of window to apply to each grain (default is Hann window (WinType.hann)).

    Args:
        world: Pointer to the MMMWorld instance.
        buf_dur: Duration of the internal buffer in seconds.
    """
    var grains: List[Grain]  
    var world: World
    var counter: Int 
    var recorder: Recorder[Self.num_chans]
    var dust: Dust[1]
    var pitch_ratios: List[Float64]
    var poly: PolyTriggerSig

    def __init__(out self, world: World, buf_dur: Float64 = 2.0, num_grains: Int = 6, max_grains: Int = 12):
        """ 
        Initialize the PitchShift struct.

        Args:
            world: Pointer to the MMMWorld instance.
            buf_dur: Duration of the internal buffer in seconds.
            num_grains: Number of grains to initialize for simultaneous playback.
            max_grains: Maximum number of grains that can be allocated for simultaneous playback. This should be greater than or equal to num_grains.
        """
        self.world = world  # Use the world instance directly
        self.grains = List[Grain]()  # Initialize the list of grains
        for _ in range(num_grains):
            self.grains.append(Grain(world)) 
            
        self.counter = 0  
        self.recorder = Recorder[Self.num_chans](world, Int(buf_dur * world[].sample_rate), world[].sample_rate)
        self.dust = Dust(world)
        self.pitch_ratios = [1.0 for _ in range(num_grains)]
        self.poly = PolyTriggerSig(num_grains, max_grains)  # Initialize the Poly struct

    @always_inline
    def next(mut self, in_sig: MFloat[Self.num_chans], grain_dur: Float64 = 0.2, overlaps: Int = 4, pitch_ratio: Float64 = 1.0, pitch_dispersion: Float64 = 0.0, time_dispersion: Float64 = 0.0, added_delay_low: Float64 = 0.0, added_delay_high: Float64 = 0.0, gain: Float64 = 1.0) -> MFloat[Self.num_chans]:
        """Generate the next set of grains for pitch shifting.

        Args:
            in_sig: Input signal to be pitch shifted.
            grain_dur: Duration of each grain in seconds.
            overlaps: Number of overlapping grains (default is 4).
            pitch_ratio: Pitch shift ratio (1.0 = no shift, 2.0 = one octave up, 0.5 = one octave down, etc).
            pitch_dispersion: Amount of random variation in pitch ratio.
            time_dispersion: Amount of random variation in grain triggering time. Value between 0.0 and 1.0, where 0.0 is no variation and 1.0 is maximum variation of up to the grain duration.
            added_delay_low: Minimum amount of delay to add to the start of each grain in seconds.
            added_delay_high: Maximum amount of delay to add to the start of each grain in seconds. (Maximum added delay should be set so that it does not exceed the internal buffer size when combined with the grain duration and time dispersion).
            gain: Amplitude scaling factor for the output.
        """

        self.recorder.write_next(in_sig)

        time_dispersion2 = clip(time_dispersion, 0.0, 0.999)

        trig_rate = Float64(overlaps) / grain_dur
        trig = self.dust.next_bool(trig_rate*(1-time_dispersion2), trig_rate*(1+time_dispersion2), trig = MBool[1](fill=True))

        _ = self.poly.next(self.grains, trig)

        out = MFloat[Self.num_chans](0.0)

        for i in range(len(self.grains)):
            start_frame = 0
            
            if trig:
                self.pitch_ratios[i] = pitch_ratio * linexp(clip(random_float64(-pitch_dispersion, pitch_dispersion), -1.0, 1.0), -1.0, 1.0, 0.25, 4.0)
                added_delay = random_float64(added_delay_low, added_delay_high)
                if self.pitch_ratios[i] <= 1.0:
                    start_frame = Int(Float64(self.recorder.write_head) - (added_delay * self.world[].sample_rate)) % self.recorder.buf.num_frames
                else:
                    start_frame = Int(Float64(self.recorder.write_head) - ((grain_dur * self.world[].sample_rate) * (self.pitch_ratios[i]-1.0)) - (added_delay * self.world[].sample_rate)) % self.recorder.buf.num_frames

            if self.poly.active_list[i]:
                out += self.grains[i].next[Self.num_chans, win_type=Self.win_type, bWrap=True](self.recorder.buf, self.pitch_ratios[i], False, start_frame, grain_dur, gain)

        return out