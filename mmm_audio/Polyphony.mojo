from mmm_audio import *

trait PolyObject(Movable, Copyable):
    def check_active(mut self) -> Bool:
        """A required, user defined function to check if the voice is active. This is usually done by checking if the envelope is active or if the Line has reached its end. This function is used internally by Poly to keep track of which voices are active and which are not.

        Returns:
            True when the voice is active, otherwise False.
        """
        ...

    # set_trigger
    def set_trigger(mut self, trigger: Bool):
        """Necessary for PolyObjects that use next_trig or next_mtrig. This function is used internally by Poly to set the PolyObject to triggered. That way, the PolyObject can open its own envelope or trigger other parameters in the subsequent `next` call.

        Usually the function will just be:

        `self.trigger = trigger`

        but there might also be some values reset if trigger is True
        
        Args:
            trigger: When this is True, the PolyObject should set its self.trigger to true and reset any variable that need to be reset.
        """
        
        pass
    
    
    def set_gate(mut self, gate: Bool):
        """Necessary for PolyObjects that use next_gate or next_mgate. This function is used internally by Poly to open and close the gate of the PolyObject.
        
        Usually the function will just be:

        `self.gate = gate`

        Args:
            gate: When this is True, the PolyObject should open its gate. When this is False, the PolyObject should close its gate.
        
        """
        pass

    def reset_Resettable(mut self):
        """Goes through every object inside of a PolyObject, checks if the object confroms to the PolyReset trait, and if it does, calls the reset function of that object.

        Objects that conform to the PolyReset trait usually need to be reset if a PolyObject is stopped and started. Delays and filters are obvious examples of this. They will have residual information in them when they are stopped, and that information needs to be cleared before the next time they are started.
        """
        comptime r = reflect[Self]()
        comptime names = r.field_names()
        comptime types = r.field_types()
        
        comptime for idx in range(r.field_count()):
            comptime comptime_field_type = types[idx]
            comptime if conforms_to(comptime_field_type, PolyReset):
                r.field_ref[idx](self).reset()

    @doc_hidden
    def reset_Resettable[T: PolyReset](mut self, mut *ugens: T):
        """A helper function for resetting objects that conform to the PolyReset trait. This version of the function takes a variable number of UGens as arguments and resets all of them. This is useful for resetting specific UGens without having to reset every PolyReset UGen in the PolyObject.

        Args:
            ugens: A variable number of UGens that conform to the PolyReset trait. These are the UGens that will be reset when this function is called.
        """
        for ref ugen in ugens:
            ugen.reset()

trait PolyReset():
    """A trait for UGens that need to be reset when a Poly voice is triggered or released. If a UGen implements this trait."""
    def reset(mut self):
        """A function called when a voice needs to be reset.
        """
        ...


struct Poly(Movable, Copyable):
    """A Poly implementation for synths triggered by signals, like TGrains and PitchShift.
    """
    var num_voices: Int
    var active_list: List[Bool]
    var changes: List[Changed[Bool]]
    var active_dict: Dict[Int, Int]
    var m: Messenger
    var world: World
    var string_dict: Dict[String, Int]
    var int_dict: Dict[Int, Int]

    def __init__(out self, world: World, num_voices: Int, namespace: Optional[String] = None):
        """Initialize the Poly.

        Args:
            world: Pointer to the MMMWorld instance.
            num_voices: The number of voices in the Poly object. This is the maximum number of voices that can be active at once. If all voices are active and a new trigger is received, the trigger will be ignored. You can increase the number of voices with the set_num_voices function, but you cannot decrease the number of voices after initialization.
            namespace: Optional message namespace for the internal Messenger.
        """
        self.num_voices = num_voices
        self.active_list = [False for _ in range(self.num_voices)]
        self.changes = [Changed[Bool](False) for _ in range(self.num_voices)]
        self.active_dict = Dict[Int, Int]()
        self.string_dict = Dict[String, Int]()
        self.int_dict = Dict[Int, Int]()
        self.m = Messenger(world, namespace)
        self.world = world

    def set_num_voices(mut self, new_num_voices: Int):
        """This function can be used to change the number of voices that the Poly can use. If more voices are needed than the initial number, you can increase the number of voices with this function.

        Args:
            new_num_voices: The new number of voices for the Poly. This can only be increased, not decreased. If the new number of voices is less than the current number of voices, this function will do nothing.
        """
        if new_num_voices > self.num_voices:
            for _ in range(new_num_voices - self.num_voices):
                self.active_list.append(False)
                self.changes.append(Changed[Bool](False))
            self.num_voices = new_num_voices

    def next_trig[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool) -> Int:
        """Looks at the value of trig. If trig is True, looks for a free voice and triggers it. Returns the index of the voice that was triggered, or -1 if no voice was triggered.

        Parameters:
            T: This value is inferred at compile time based on the type of the poly_objects list. This is the type of the PolyObjects that are being triggered.

        Args:
            poly_objects: A list of structs conforming to the PolyObject trait. The Poly will look for a free voice in this list and trigger it when trig is True.
            trig: A boolean value that triggers a voice when it is True.

        Returns:
            The index of the voice that was triggered, or -1 if no voice was triggered.
        """
        self._reset[audio_control = 0](poly_objects)
        return self.find_voice_and_trigger(poly_objects, trig)

    def next_trig[T: PolyObject](mut self, 
        mut poly_objects: List[T], 
        trig: Bool, 
        call_back: def(mut poly_object: T, trig: Bool) capturing -> None
    ) -> Int:
        self._reset[audio_control = 0](poly_objects)
        voice_index = self.find_voice_and_trigger(poly_objects, trig)
        if voice_index != -1:
            call_back(poly_objects[voice_index], trig)
        return voice_index

    def next_mtrig[
        T: PolyObject,
        call_back: def (mut poly_object: T, mut vals: List[Int]) capturing -> None,
    ](mut self, mut poly_objects: List[T]):
        """Convenience function triggered by Python messages.

        This convenience function achieves all functionality of a Poly that is being 
        triggered by messages from Python. It resets the Poly at the beginning of each 
        block, looks for triggers from Python, and triggers PolyObjects as needed. 

        The optional call_back function is called whenever a new trigger is received 
        from Python. `next_mtrig` has to be paired with messages sent from Python as a 
        List[Int], List[Float64], Int, or Float64. The call_back function receives the 
        List or value so the PolyObject can be controlled by the message from Python.

        Parameters:
            T: The type of the PolyObjects that are being triggered. Inferred at compile 
                time based on the type of the poly_objects list.
            call_back: A function called whenever a new trigger is received from Python 
                used to control the parameters of the triggered PolyObject.
                
                Args:
                    poly_object: The specific PolyObject instance being controlled.
                    vals: The runtime trigger message parameters sent from Python.
                
                There are four versions of next_mtrig differentiated by the type of this 
                `vals` parameter (List[Int], List[Float64], Int, or Float64) paired with 
                send_ints, send_floats, send_int, and send_float on the Python side.

        Args:
            poly_objects: A list of structs conforming to the PolyObject trait. This is 
                the list of PolyObjects that we are controlling.
        """

        self._reset[audio_control = 1](poly_objects)
        vals = List[Int]()
        for i in range(self.num_voices):
            trig = self.m.notify_update(String(i), vals)
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], vals)
    
    def next_mtrig[T: PolyObject, call_back: def (mut poly_object: T, mut vals: List[Float64]) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset[audio_control = 1](poly_objects)
        vals = List[Float64]()
        for i in range(self.num_voices):
            trig = self.m.notify_update(String(i), vals)
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], vals)

    def next_mtrig[T: PolyObject, call_back: def (mut poly_object: T, mut val: Int) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset[audio_control = 1](poly_objects)
        val: Int = 0
        for i in range(self.num_voices):
            trig = self.m.notify_update(String(i), val)
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], val)
    
    def next_mtrig[T: PolyObject, call_back: def (mut poly_object: T, mut val: Float64) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset[audio_control = 1](poly_objects)
        val: Float64 = 0.0
        for i in range(self.num_voices):
            trig = self.m.notify_update(String(i), val)
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], val)

    def next_gate[T: PolyObject](mut self, mut poly_objects: List[T], gate_sigs: List[Bool]) -> Int:
        """This function is designed to be used with polyphonic synths that have gated controls that are signals.

        Parameters:
            T: The PolyObject type stored in `poly_objects`.

        Args:
            poly_objects: A list of structs conforming to the PolyObject trait. This function calls the set_gate function for each PolyObject to open and close the gates as needed.
            gate_sigs: A list of boolean signals that control the gates of the voices. This number should be less than or equal to the number of voices in the Poly. Remember that even if a gate is closed that does not mean the voice is free. The voice is free when the envelope or Line of the voice is finished and the check_active function returns False again. Plan the number of gates and voices accordingly.

        Returns:
            The index of the voice whose gate was opened, or -1 if no voice was opened.
        """
        self._reset[audio_control = 0](poly_objects)
        for i in range(len(gate_sigs)):
            changed = self.changes[i].next(gate_sigs[i])
            if changed:
                if gate_sigs[i]: # if the signal went from False to True, trigger the note on for that gate
                    return self._find_voice_and_open_gate(poly_objects, changed, Int(i))
                else:
                    _ = self._close_gate(poly_objects, Int(i))
        return -1

    def next_mgate[
        T: PolyObject,
        call_back: def (mut poly_object: T, mut vals: List[Int]) capturing -> None
    ](
        mut self, 
        mut poly_objects: List[T]
    ):
        """This function is designed to be used with polyphonic synths that have gated controls that are controlled by messages from Python. There are two versions of `next_mgate`, one that receives messages as a List[Int] and one that receives messages as a List[Float64]. The type of the message is differentiated by the type of the `vals` parameter in the call_back function. The call_back function is called whenever a new message is received from Python.

        Parameters:
            T: This value is inferred at compile time based on the type of the poly_objects list. This is the type of the PolyObjects that are being triggered.
            call_back: A function that is called whenever a new trigger is received from Python. This can be used to control the parameters of the triggered PolyObject with the message from Python. The type of the message from Python is differentiated by the type of the `vals` parameter in the call_back function. The type can be a List[Int], a List[Float64], which is paired with send_ints and send_floats respectively on the Python side. The call_back function receives the List or value so the PolyObject can be controlled by the message from Python.

        Args:
            poly_objects: A list of structs conforming to the PolyObject trait. This function calls the set_gate function for each PolyObject to open and close the gates as needed.
        """
        self._reset[audio_control = 1](poly_objects)
        if self.world[].top_of_block():
            vals = List[Int]()
            for i in range(self.num_voices):
                trig = self.m.notify_update(String(i), vals)
                if trig:
                    if vals[1] > 0: # if the velocity is greater than 0, trigger the note on
                        free_voice = self._find_voice_and_open_gate(poly_objects, trig, vals[0]) # get the index of the free voice
                        if free_voice >= 0:
                            call_back(poly_objects[free_voice], vals)
                    else: # if the velocity is 0, trigger the note off for that note
                        # close the gate for the voice that is playing and forget that is was playing
                        freed_voice = self._close_gate(poly_objects, vals[0])
                        if freed_voice >= 0:
                            call_back(poly_objects[freed_voice], vals)

    def next_mgate[
        T: PolyObject, 
        call_back: def(mut poly_object: T, mut vals: List[Float64]) capturing -> None
    ](
        mut self, 
        mut poly_objects: List[T]
    ):
        self._reset[audio_control = 1](poly_objects)

        if self.world[].top_of_block():
            # Explicit type variable instantiation using 'var'
            var vals = List[Float64]() 
            
            for i in range(self.num_voices):
                # Mojo 1.0 requires explicit var definitions for block scope bindings
                var trig = self.m.notify_update(String(i), vals) 
                
                if trig:
                    if vals[1] > 0.0: 
                        # Note On Event Tracking
                        var free_voice = self._find_voice_and_open_gate(
                            poly_objects, trig, String(vals[0])
                        )
                        if free_voice != -1:
                            call_back(poly_objects[free_voice], vals)
                    else: 
                        # Note Off Event Tracking
                        var freed_voice = self._close_gate(poly_objects, String(vals[0]))
                        if freed_voice != -1:
                            call_back(poly_objects[freed_voice], vals)

    @doc_hidden
    def _reset[T: PolyObject, audio_control: Int](mut self, mut poly_objects: List[T]):
        """Must be called before any subsequent calls to find_voice_and_trigger or _find_voice_and_open_gate. This function resets the triggered state of all voices at the beginning of each block or every sample, depending on the only_top_of_block parameter.
        """
        comptime if audio_control == 0:
            for i in range(len(poly_objects)):
                self.active_list[i] = poly_objects[i].check_active()
                poly_objects[i].set_trigger(False)
        else:
            if self.world[].top_of_block():
                for i in range(len(poly_objects)):
                    self.active_list[i] = poly_objects[i].check_active()
            else: 
                if self.world[].block_state() == 1:
                    for i in range(len(poly_objects)):
                        poly_objects[i].set_trigger(False)

    @doc_hidden
    def _find_free_voice[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool) -> Int:
        trigger_grain = -1
        if trig:
            list_len = len(self.active_list)
            trigger_grain, add_voice_bool = self._find_voice(list_len)
            if add_voice_bool:
                    trigger_grain = -1
                    print("Max polyphony reached, cannot add more voices.")

        return trigger_grain

    @doc_hidden
    def _find_voice(mut self, list_len: Int) -> Tuple[Int, Bool]:
        found = False
        counter = 0
        while not found and counter < list_len:
            if not self.active_list[counter]:
                found = True
            else:
                counter += 1
        if found:
            self.active_list[counter] = True
            return (counter, False)  
        else:
            counter = list_len  # this is the index of the next voice to be added 
            return (counter, True) 

    def find_voice_and_trigger[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool) -> Int:
        trigger_grain = self._find_free_voice(poly_objects, trig)

        if trigger_grain != -1:
            poly_objects[trigger_grain].set_trigger(True)

        return trigger_grain

    @doc_hidden
    def _find_voice_and_open_gate[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool, key: String) -> Int:
        trigger_grain = self._find_free_voice(poly_objects, trig)
        if trigger_grain != -1:
            self._open_gate(poly_objects, key, trigger_grain)
        return trigger_grain

    def _find_voice_and_open_gate[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool, key: Int) -> Int:
        trigger_grain = self._find_free_voice(poly_objects, trig)
        if trigger_grain != -1:
            self._open_gate(poly_objects, key, trigger_grain)
        return trigger_grain

    @doc_hidden
    def _open_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: Int, active_list_index: Int):
        poly_objects[active_list_index].set_gate(True)
        self.int_dict[key] = active_list_index

    @doc_hidden
    def _open_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: String, active_list_index: Int):
        poly_objects[active_list_index].set_gate(True)
        self.string_dict[key] = active_list_index

    @doc_hidden
    def _close_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: String) -> Int:
        active_list_index = self.string_dict.pop(key, -1)
        if active_list_index != -1:
            poly_objects[active_list_index].set_gate(False)
        return active_list_index

    @doc_hidden
    def _close_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: Int) -> Int:
        active_list_index = self.int_dict.pop(key, -1)
        if active_list_index != -1:
            poly_objects[active_list_index].set_gate(False)
        return active_list_index

from mmm_audio import *

trait GrainObject(PolyObject):
    """Trait for objects that can be used as grains in the TGrains struct for triggered granular synthesis."""

    def __init__(out self, world: World):
        """Initialize a GrainObject implementation.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        ...

    def next_2[num_buf_chans: Int, num_playback_chans: Int = 2, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_buf_chans]) -> MFloat[2]:
        """This is the function to create if you want to output 2 channels using pan2 or pan_stereo.

        Parameters:
            num_buf_chans: Number of channels in the source buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            num_playback_chans: Number of source channels to play back before panning.
            win_type: Window type applied to the grain.
            custom_curve: Optional custom curve for user-defined envelopes.
            bWrap: Whether reads wrap around the source buffer.

        Args:
            buffer: Source buffer for grain playback.

        Returns:
            The next stereo grain sample.
        """
        return 0.0

    def next_multi_channel[num_buf_chans: Int, num_speakers: Int = 2, num_simd_chans: Int = 2, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_buf_chans], buffer_chan: Int = 0) -> MFloat[num_simd_chans]:
        """Get the next sample of the grain as a multi-channel signal. By default, Grain uses azimuth panning with a width of 2.0 and an orientation of 0.5. However, you can use dbap or any other panning algorithm by creating a custom grain with its own next_multi_channel function. This only pans 1 channel of the buffer, specified by buffer_chan. See next_2 for param/arg descriptions.

        Parameters:
            num_buf_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            num_speakers: The number of speakers in the system. This is used for calculating the azimuth panning.
            num_simd_chans: The number of channels in the output sample. This must be a power of two and should be greater than or equal to num_speakers. If num_simd_chans is greater than num_speakers, the extra channels will just be 0.0.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (Env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.
            buffer_chan: The channel of the buffer to read from for panning. This should be less than num_buf_chans.

        Returns:
            A multi-channel sample of the grain with azimuth panning applied.
        """
        return 0.0

    def next_all[num_chans: Int, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_chans]) -> MFloat[num_chans]:
        """
        Get the next sample of the grain. This function returns all channels of the buffer with no panning.
        
        Parameters:
            num_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.

        Returns:
            A multi-channel sample of the grain. The number of channels is the same as the number of channels in the buffer.
        """
        return 0.0

    def set_env_trigger(mut self, trigger: Bool):
        """Sets the envelope trigger for the internal grain. This sets the value so that the next time the grain's next function is called, the grain will know to trigger or not trigger the envelope.

        Args:
            trigger: Sets the envelope trigger for the internal grain to True or False.
        
        Should probably just be: self.grain.set_env_trigger(trigger)."""
        pass

    def get_env_trigger(mut self) -> Bool:
        """Checks the root grain to see if it has been triggered. Should probably just be: return self.grain.get_env_trigger().
        
        Returns:
            True if the grain has been triggered, otherwise False.
        """
        return False

    def set_user_defined_env(mut self, env_points: Span[Tuple[Float64, Float64], ...]):
        """Should probably just be: self.grain.set_user_defined_env(env_points).
        
        Args:
            env_points: A list of (time, value) tuples that define the user defined envelope. The times and values should be between 0 and 1.
        """
        ...

    def set_play_rate(mut self, ratio: Float64):
        """Set the play ratio of the grain. Normally a grain is triggered with a set playback speed, but this function allows you to change the playback speed of the grain after it has been triggered.

        Args:
            ratio: The play ratio of the grain.
        """
        pass

    def reset(mut self):
        """Reset the grain to its initial state. This can be used to retrigger the grain with the same parameters."""
        pass


struct GrainAll(GrainObject):
    """A single grain for granular synthesis. Returns all channels of a SIMDBuffer and does no panning.

    Used as part of the TGrains and the PitchShift structs for triggered granular synthesis. It is also used internally by Grain or any custom GrainObject created by the user.
    """
    var world: World  # Pointer to the MMMWorld instance

    var start_frame: Float64
    var buf_ratio: Float64  
    var rate: Float64  
    var pan: Float64  
    var gain: Float64 
    var rising_bool_detector: RisingBoolDetector[1]
    var play_buf: Play
    var line: Line[]
    var active: Bool
    var dur: Float64
    var trigger: Bool
    var user_defined_env: List[Tuple[Float64, Float64]]
    var env_trigger: Bool
    var curve: Float64
    var prev_phase: Float64
    var buf_phase: Float64

    def __init__(out self, world: World):
        self.world = world  
        self.start_frame = 0
        self.buf_ratio = 1.0
        self.rate = 1.0
        self.pan = 0.5 
        self.gain = 1.0
        self.rising_bool_detector = RisingBoolDetector() 
        self.play_buf = Play(world)
        self.line = Line[](world)
        self.line.phase = 1.0
        self.active = False
        self.dur = 1.0
        self.trigger = False
        self.user_defined_env = List[Tuple[Float64, Float64]]()
        self.user_defined_env.append((0.0, 0.0))
        self.user_defined_env.append((0.5, 1.0))
        self.user_defined_env.append((1.0, 0.0))
        self.env_trigger = False
        self.curve = 1.0
        self.buf_phase = 0.0
        self.prev_phase = 0.0

    # These are the functions that need to be implemented for the PolyObject trait:
    def check_active(mut self) -> Bool:
        return self.active

    def set_trigger(mut self, trigger: Bool):
        self.trigger = trigger
        if trigger:
            self.active = True
    # ------------------------------------------------

    def set_env_trigger(mut self, trigger: Bool):
        self.env_trigger = trigger

    def get_env_trigger(self) -> Bool:
        return self.env_trigger
    
    def set_user_defined_env(mut self, env_points: Span[Tuple[Float64, Float64], ...]):
        self.user_defined_env.clear()
        self.user_defined_env.extend(env_points)

    def set_vals(mut self, 
    rate: Float64 = 1.0, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0,
    pan: Float64 = 0.0,
    gain: Float64 = 1.0,
    curve: Float64 = 1.0):
        """Set the Grain's variables.

        Args:
            rate: Playback rate of the grain (1.0 = normal speed).
            start_frame: Starting frame position in the buffer.
            duration: Duration of the grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right). As this function is used by the panning functions, the pan value is saved to self.pan in this function when a trigger is received, but there is no direct use of it here.
            gain: Amplitude scaling factor for the grain.
            curve: The curve shape for the user-defined envelope.
        """
        self.rate = rate
        self.start_frame = Float64(start_frame)
        self.buf_ratio = duration * rate
        self.dur = duration
        self.gain = gain
        self.pan = pan
        self.curve = curve

    def set_play_rate(mut self, ratio: Float64):
        """Set the play rate of the grain. Normally a grain is triggered with a set playback speed, but this function allows you to change the playback speed of the grain after it has been triggered.

        Args:
            ratio: The play rate of the grain.
        """
        self.buf_ratio = self.dur*ratio

    def next_all[num_chans: Int, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_chans]) -> MFloat[num_chans]:
        """
        Get the next sample of the grain. This function returns all channels of the buffer with no panning.
        
        Parameters:
            num_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.

        Returns:
            A multi-channel sample of the grain. The number of channels is the same as the number of channels in the buffer.
        """

        phase = self.line.next(0.0, 1.0, self.dur, self.trigger)
        if self.trigger:
            self.buf_phase = self.start_frame / Float64(buffer.num_frames)

        phase_diff = self.line.freq * self.line.freq_mul
        self.prev_phase = phase
        
        self.buf_phase = self.buf_phase + phase_diff * self.buf_ratio / buffer.duration
        
        # (phase * self.buf_ratio)/buffer.duration + (self.start_frame / Float64(buffer.num_frames))

        sample = buf_read[interp=Interp.linear, bWrap=bWrap](self.world, buffer, self.buf_phase)

        comptime if win_type == WindowType.user_defined:
            win = env[win_type=custom_curve](self.world, phase, self.user_defined_env, self.curve)
        else:
            win = win_read[win_type, Interp.linear](self.world, phase)

        if phase >= 1.0:
            self.active = False

        # this only works with 1 or 2 channels, if you try to do more, it will just return 2 channels
        sample = sample * win * self.gain  # Apply the window to the sample
        
        return sample

    def reset(mut self):
        self.active = False
        self.trigger = False

struct Grain(GrainObject):
    """A single grain for granular synthesis with multiple output options: next_2, next_multi_channel, next_all. Used as part of the TGrains and the PitchShift structs for triggered granular synthesis.
    """
    var world: World 
    var grain: GrainAll
    var start_chan: Int

    def __init__(out self, world: World):
        """Initialize the grain.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world  
        self.grain = GrainAll(world)
        self.start_chan = 0

    @doc_hidden
    def check_active(mut self) -> Bool:
        return self.grain.check_active()

    @doc_hidden
    def set_trigger(mut self, trigger: Bool):
        self.grain.set_trigger(trigger)
    
    @doc_hidden
    def set_env_trigger(mut self, trigger: Bool):
        self.grain.set_env_trigger(trigger)

    @doc_hidden
    def get_env_trigger(self) -> Bool:
        return self.grain.get_env_trigger()

    def set_user_defined_env(mut self, env_points: Span[Tuple[Float64, Float64], ...]):
        """Set a the EnvParams of a user-defined envelope for the grain. This allows you to use a custom envelope shape instead of the built-in window types.
        
        Args:
            env_points: The points for the user-defined envelope. This should be a list of tuples with the desired envelope settings.
        """
        self.grain.set_user_defined_env(env_points)

    def set_vals(mut self, 
    rate: Float64 = 1.0, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0,
    pan: Float64 = 0.0,
    gain: Float64 = 1.0,
    start_chan: Int = 0,
    curve: Float64 = 1.0):
        """Set the Grain's variables.

        Args:
            rate: Playback rate of the grain (1.0 = normal speed).
            start_frame: Starting frame position in the buffer.
            duration: Duration of the grain in seconds.
            pan: Panning position from -1.0 (left) to 1.0 (right). As this function is used by the panning functions, the pan value is saved to self.pan in this function when a trigger is received, but there is no direct use of it here.
            gain: Amplitude scaling factor for the grain.
            start_chan: The first buffer channel to read from for the grain (default: 0). If num_playback_chans is 2, the grain will read from start_chan and start_chan+1 for the left and right channels, respectively.
            curve: The curve shape for the user-defined envelope.
        """
        self.grain.set_vals(rate, start_frame, duration, pan, gain, curve)
        self.start_chan = start_chan

    def next_2[
        num_buf_chans: Int, 
        num_playback_chans: Int = 2, 
        win_type: WindowType = WindowType.hann, 
        custom_curve: WindowType = WindowType.none, 
        bWrap: Bool = False
    ](mut self, buffer: SIMDBuffer[num_buf_chans]) -> MFloat[2]:
        """Get the next sample of the grain as a stereo signal with panning.
        
        Parameters:
            num_buf_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            num_playback_chans: Either 1 or 2, depending on whether you want to pan 1 channel of the buffer out 2 channels or 2 channels of the buffer with equal power panning.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (Env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.

        Returns:
            A stereo sample of the grain with panning applied.
        """
        
        var sample = self.grain.next_all[win_type=win_type, bWrap=bWrap](buffer)

        comptime if num_playback_chans == 1:
            panned = pan2(sample[self.start_chan], self.grain.pan)
            return panned
        else:
            panned = pan_stereo(MFloat[2](sample[self.start_chan], sample[(self.start_chan + 1) % buffer.get_num_chans()]), self.grain.pan) 
            return panned

    def next_multi_channel[num_buf_chans: Int, num_speakers: Int = 2, num_simd_chans: Int = 2, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_buf_chans], buffer_chan: Int = 0) -> MFloat[num_simd_chans]:
        """Get the next sample of the grain as a multi-channel signal. By default, Grain uses azimuth panning with a width of 2.0 and an orientation of 0.5. This only pans 1 channel of the buffer, specified by buffer_chan. See next_2 for param/arg descriptions and pan_az for details on the panning parameters.

        Parameters:
            num_buf_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            num_speakers: The number of speakers in the system. This is used for calculating the azimuth panning.
            num_simd_chans: The number of channels in the output sample. This must be a power of two and should be greater than or equal to num_speakers. If num_simd_chans is greater than num_speakers, the extra channels will just be 0.0.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (Env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.
            buffer_chan: The channel of the buffer to read from for panning. This should be less than num_buf_chans.

        Returns:
            A multi-channel sample of the grain with azimuth panning applied.
        """
        var sample = self.grain.next_all[win_type=win_type, bWrap=bWrap](buffer)

        panned = pan_az[num_speakers, num_simd_chans, 2, 0.5](sample[buffer_chan], self.grain.pan) 

        return panned

    def next_all[num_chans: Int, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_chans]) -> MFloat[num_chans]:
        """Get the next sample of the grain with no panning. This returns all channels of the buffer.

        Parameters:
            num_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            win_type: The type of window to apply to the grain. A hann window is used by default, and will give the classic granular synthesis sound. If win_type is WindowType.user_defined, then the user_defined_env (Env) will be used as the window.
            custom_curve: If win_type is WindowType.user_defined, applies a custom curve to the user defined envelope. This is the win_type parameter of the Env next function.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.

        Args:
            buffer: A SIMDBuffer to read from.

        Returns:
            A sample of the grain with num_chans channels.
        """
        var sample = self.grain.next_all[win_type=win_type, bWrap=bWrap](buffer)
        return sample
    
    def reset(mut self):
        """Reset the grain to its initial state. This can be used to retrigger the grain with the same parameters."""
        self.grain.reset()

    def set_play_rate(mut self, rate: Float64):
        """Set the play rate of the grain. Normally a grain is triggered with a set playback speed, but this function allows you to change the playback speed of the grain after it has been triggered.

        Args:
            rate: The play rate of the grain.
        """
        self.grain.set_play_rate(rate)

struct TGrains[T: GrainObject = Grain[], win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.none](Movable, Copyable, PolyReset):
    """
    Triggered granular synthesis. Each trigger starts a new grain.
    """
    var num_grains: Int
    var grains: List[Self.T] 
    var world: World
    var poly: Poly
    var env_points: List[Tuple[Float64, Float64]] 
    var grain_index: Int

    def __init__(out self, world: World, num_grains: Int = 1):
        """
        Initialize the TGrains struct.

        Args:
            world: Pointer to the MMMWorld instance.
            num_grains: Number of grains to initialize.
        """
        self.num_grains = num_grains
        self.world = world  
        self.grains = List[Self.T]() 
        for _ in range(num_grains):
            self.grains.append(Self.T(world))
        self.poly = Poly(world, num_grains) 
        self.env_points = List[Tuple[Float64, Float64]]()  # Initialize with default parameters
        self.grain_index = -1

    def set_num_grains(mut self, new_num_grains: Int):
        """This function can be used to change the number of grains that the Poly can use. If more grains are needed than the initial number, you can increase the number of grains with this function.

        Args:
            new_num_grains: The new number of grains that the Poly should be able to use. This should be greater than the current number of grains. If it is less than the current number of grains, this function will do nothing.
        """
        if new_num_grains > self.num_grains:
            self.poly.set_num_voices(new_num_grains)
            for _ in range(new_num_grains - self.num_grains):
                self.grains.append(Self.T(self.world))
            self.num_grains = new_num_grains

    def set_env_points(mut self, env_points: Span[Tuple[Float64, Float64], ...]):
        """Set the envelope points for all grains by providing Span (List or InlineArray) of tuples. This allows you to use a custom envelope shape instead of the built-in window types. Will update each grain on its next trigger. The tuples should be in the format (x, y), where x is the position in the grain from 0.0 to 1.0 and y is the amplitude at that point. For example, set_env_points((0.0, 0.0), (0.5, 1.0), (1.0, 0.0)) would be a simple triangle envelope.

        Args:
            env_points: A List or other Span of tuples defining the envelope shape.
        """
        self.env_points.clear()
        for point in env_points:
            self.env_points.append(point)
        # set all the grains to update their user_defined_env with the new env on the next trigger
        for ref grain in self.grains:
            grain.set_env_trigger(True)

    def set_env_points(mut self, env_points: List[Float64]):
        """Set the envelope points for all grains by providing a list of values. This allows you to use a custom envelope shape instead of the built-in window types. Will update each grain on its next trigger.

        Args:
            env_points: A List or other Span of values defining the envelope shape. Each 2 values represent an env_point, so the list should be in the format [x1, y1, x2, y2, ...], where x is the position in the grain from 0.0 to 1.0 and y is the amplitude at that point. For example, [0.0, 0.0, 0.5, 1.0, 1.0, 0.0] would be a simple triangle envelope.
        """
        self.env_points.clear()
        for i in range(len(env_points)//2):
            self.env_points.append((env_points[i*2], env_points[i*2+1]))
        # set all the grains to update their user_defined_env with the new env on the next trigger
        for ref grain in self.grains:
            grain.set_env_trigger(True)

    
    def trig(mut self, trig: Bool) -> Int:
        """Send the trigger signal to the TGrains. If trig is True, looks for a free grain, sets its self.trigger flag to True, and makes the grain active.

        Args:
            trig: A boolean trigger signal. When True, the TGrains will look for a free grain to trigger. When False, no new grains will be triggered.

        Returns:
            The index of the grain that was triggered, or -1 if no grain was triggered.
        """
        comptime if Self.win_type == WindowType.user_defined:            
            self.grain_index = self.poly.next_trig(self.grains, trig)
            if self.grain_index >= 0:
                if self.grains[self.grain_index].get_env_trigger() and trig:
                    self.grains[self.grain_index].set_user_defined_env(self.env_points)
                    self.grains[self.grain_index].set_env_trigger(False)
        else:
            self.grain_index = self.poly.next_trig(self.grains, trig)
        return self.grain_index

    @always_inline
    def next_2[num_playback_chans: Int = 1, bWrap: Bool = False](mut self, buffer: SIMDBuffer, gain: Float64 = 1.0) -> MFloat[2]:
        """Generate the next set of grains. Depending on num_playback_chans, will either pan a mono signal out 2 channels or a stereo signal out 2 channels.
        
        Parameters:
            num_playback_chans: Either 1 or 2, depending on whether you want to pan 1 channel of a buffer out 2 channels or 2 channels of the buffer with equal power panning.
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            gain: Amplitude scaling factor for the output of the grains.

        Returns:
            Output samples for the left and right channels.
        """

        out = MFloat[2](0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                out += self.grains[i].next_2[win_type=Self.win_type, custom_curve=Self.custom_curve, bWrap=bWrap](buffer)
        return out * gain

    @always_inline
    def next_multi_channel[num_buf_chans: Int, num_speakers: Int = 2, num_simd_chans: Int = 2, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_buf_chans], buffer_chan: Int = 0, gain: Float64 = 1.0) -> MFloat[num_simd_chans]:
        """Get the next sample of the grain as a multi-channel signal with azimuth panning. This only pans 1 channel of the buffer, specified by buffer_chan. See next_2 for param/arg descriptions and pan_az for details on the panning parameters.

        Parameters:
            num_buf_chans: The number of channels in the buffer. This is inferred at compile time based on the channel count of the SIMDBuffer that is passed in.
            num_speakers: The number of speakers in the system. This is used for calculating the azimuth panning.
            num_simd_chans: The number of channels in the output sample. This must be a power of two and should be greater than or equal to num_speakers. If num_simd_chans is greater than num_speakers, the extra channels will just be 0.0.
            bWrap: Whether to wrap around the buffer when reading. If false, the grain will read 0 when it reaches the end of the buffer. If true, the grain will wrap around to the beginning of the buffer when it reaches the end.
        
        Args:
            buffer: A SIMDBuffer to read from.
            buffer_chan: The channel of the buffer to read from for panning. This should be less than num_buf_chans.
            gain: Amplitude scaling factor for the output of the grains.

        Returns:
            A multi-channel sample of the grain with azimuth panning applied.
        """

        out = MFloat[num_simd_chans](0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                out += self.grains[i].next_multi_channel[num_speakers=num_speakers, num_simd_chans=num_simd_chans, win_type=Self.win_type, custom_curve=Self.custom_curve, bWrap=bWrap](buffer, buffer_chan)
        return out * gain

    @always_inline
    def next_all[num_chans: Int, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_chans], gain: Float64 = 1.0) -> MFloat[num_chans]:
        """Generate the next set of grains. Depending on num_out_chans, will either pan a mono signal out 2 channels or a stereo signal out 2 channels.
        
        Parameters:
            num_chans: A power of two num out channels that will determine the size of the SIMD output.
            bWrap: Whether to interpolate between the end and start of the buffer when reading (default: False). When False, reading beyond the end of the buffer will return 0. When True, the index into the buffer will wrap around to the beginning using a modulus.

        Args:
            buffer: Audio buffer containing the source sound.
            gain: Amplitude scaling factor for the output of the grains.

        Returns:
            Output samples for left and right channels as a SIMD vector.
        """

        out = MFloat[num_chans](0.0)
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                out += self.grains[i].next_all[win_type=Self.win_type, custom_curve=Self.custom_curve, bWrap=bWrap](buffer)
        return out * gain

    def reset(mut self):
        """Reset all grains to be inactive and set their triggers to False. This can be used to stop all grains immediately.
        """
        for ref grain in self.grains:
            grain.reset()

    def set_play_rate(mut self, ratio: Float64):
        """Set the play ratio of all active grains. This allows you to change the playback speed of all currently active grains at once.

        Args:
            ratio: The play ratio to set for all active grains.
        """
        for i in range(len(self.grains)):
            if self.poly.active_list[i]: 
                self.grains[i].set_play_rate(ratio)

struct PitchShift[num_chans: Int = 1, win_type: WindowType = WindowType.hann](Movable, Copyable, PolyReset):
    """
    An N channel granular pitchshifter. Each channel is processed in parallel.

    Parameters:
        num_chans: Number of input/output channels.
        win_type: Type of window to apply to each grain (default is Hann window (WinType.hann)).

    Args:
        world: Pointer to the MMMWorld instance.
        buf_dur: Duration of the internal buffer in seconds.
    """
    var tgrains: TGrains[Grain, Self.win_type]
    var world: World
    var counter: Int 
    var recorder: Recorder[Self.num_chans]
    var dust: Dust[1]
    var num_grains: Int

    def __init__(out self, world: World, buf_dur: Float64 = 2.0, num_grains: Int = 12):
        """ 
        Initialize the PitchShift struct.

        Args:
            world: Pointer to the MMMWorld instance.
            buf_dur: Duration of the internal buffer in seconds.
            num_grains: Number of grains to initialize for simultaneous playback.
        """
        self.world = world  # Use the world instance directly
        self.tgrains = TGrains[Grain, Self.win_type](self.world, num_grains)
        self.num_grains = num_grains

        self.counter = 0  
        self.recorder = Recorder[Self.num_chans](world, Int(buf_dur * world[].sample_rate), world[].sample_rate)
        self.dust = Dust(world)

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

        Returns:
            The next sample of the pitch-shifted signal as a SIMD vector with num_chans channels.
        """

        self.recorder.write_next(in_sig)

        time_dispersion2 = clip(time_dispersion, 0.0, 0.999)

        trig_rate = Float64(overlaps) / grain_dur

        trig = self.dust.next_bool(trig_rate*(1-time_dispersion2), trig_rate*(1+time_dispersion2), trig = MBool[1](fill=True))
        grain_num = self.tgrains.trig(trig)

        if grain_num >= 0:
            
            added_delay = random_float64(added_delay_low, added_delay_high)
            pitch_ratio2 = pitch_ratio * linexp(clip(random_float64(-pitch_dispersion, pitch_dispersion), -1.0, 1.0), -1.0, 1.0, 0.25, 4.0)
            if pitch_ratio2 <= 1.0:
                start_frame = Int(Float64(self.recorder.write_head) - (added_delay * self.world[].sample_rate)) % self.recorder.buf.num_frames
            else:
                start_frame = Int(Float64(self.recorder.write_head) - ((grain_dur * self.world[].sample_rate) * (pitch_ratio2-1.0)) - (added_delay * self.world[].sample_rate)) % self.recorder.buf.num_frames
            self.tgrains.grains[grain_num].set_vals(pitch_ratio2, start_frame, grain_dur, 0.0, gain, 0)

        out = self.tgrains.next_all[Self.num_chans, bWrap = True](self.recorder.buf, gain)

        return out

    def reset(mut self):
        """Reset the PitchShift to its initial state. This will clear the internal buffer and reset all grains."""
        self.tgrains.reset()