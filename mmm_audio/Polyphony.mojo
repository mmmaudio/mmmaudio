from mmm_audio import *

trait PolyObject(Movable, Copyable):
    def check_active(mut self) -> Bool:
        """A required, user defind function to check if the voice is active. This is usually done by checking if the envelope is active or if a Play object is still playing. This function is used internally by Poly to keep track of which voices are active and which are not.
        """
        ...

    # set_trigger
    def set_trigger(mut self, trigger: Bool):
        """Necessary for triggered PolyObjects. This function is used internally by Poly to set the PolyObject to triggered. That way, the PolyObject can open its own envelope or trigger other parameters in the subsequent `next` call."""
        # self.trigger = trigger # usually it is just this
        pass
    
    # set_gate is helpful in polyphonic synths with ASR or ADSR envelopes
    def set_gate(mut self, gate: Bool):
        """Necessary for gated PolyObjects. This function is used internally by PolyGate and PolyGateSig to open and close the gate of the PolyObject."""
        # usually it is just this
        # self.gate = False
        pass

    def reset_env(mut self):
        """Necessary for gated PolyObjects that use gated envelopes. This is needed because Poly will internally copy a living PolyObject to create a new voice, and this can result in a hung voice if the env is already active when it's copied.
        """
        # usually you just need a new env
        # self.env = ASREnv(self.world)
        pass

struct PolyTrigger(Movable, Copyable):
    """A Poly implementation that has an internal Messenger for handling messages from Python. The `next` function is designed to be used with messages that simply trigger a voice. Use PolyGate for messages that open and close gates.

    PolyTrigger is designed to be paired with the PolyPal class in Python. Give them the same name_space and num_messages arguments, and the messages sent from Python with PolyPal will be correctly received by the PolyTrigger object.
    """
    var poly: PolyTriggerSig
    var m: Messenger
    var num_messages: Int
    var world: World

    def __init__(out self, initial_num_voices: Int, max_voices: Int, world: World, name_space: String, num_messages: Int = 10):
        self.poly = PolyTriggerSig(initial_num_voices=initial_num_voices, max_voices=max_voices)
        self.m = Messenger(world, name_space)
        self.num_messages = num_messages
        self.world = world

    @doc_hidden
    def _reset[T: PolyObject](mut self, mut poly_objects: List[T]):
        if self.world[].top_of_block:
            for i in range(len(poly_objects)):
                self.poly.active_list[i] = poly_objects[i].check_active()
        else: 
            if self.world[].block_state == 1:
                for i in range(len(poly_objects)):
                    poly_objects[i].set_trigger(False)

    def next[T: PolyObject, call_back: def (mut poly_object: T, mut vals: List[Int]) capturing -> None](mut self, mut poly_objects: List[T]):
        """This convenience function acheives all functionality of a Triggered PolyObject synth in one function. It resets the Poly at the beginning of each block, looks for triggers from Python, and triggers PolyObjects as needed. The optional call_back function is called whenever a new trigger is received from Python. `next` has to be paired with messages sent from Python as a List[Int] or a List[Float64] or an Int or a Float64. The call_back function receives the List or value as the second argument, so the PolyObject can be controlled by the message from Python.
        """
        self._reset(poly_objects)
        vals = List[Int]()
        for i in range(self.num_messages):
            trig = self.m.notify_update(vals, String(i))
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.poly.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], vals)
    
    def next[T: PolyObject, call_back: def (mut poly_object: T, mut vals: List[Float64]) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset(poly_objects)
        vals = List[Float64]()
        for i in range(self.num_messages):
            trig = self.m.notify_update(vals, String(i))
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.poly.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], vals)

    def next[T: PolyObject, call_back: def (mut poly_object: T, mut val: Int) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset(poly_objects)
        val: Int = 0
        for i in range(self.num_messages):
            trig = self.m.notify_update(val, String(i))
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.poly.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], val)
    
    def next[T: PolyObject, call_back: def (mut poly_object: T, mut val: Float64) capturing -> None](mut self, mut poly_objects: List[T]):
        self._reset(poly_objects)
        val: Float64 = 0.0
        for i in range(self.num_messages):
            trig = self.m.notify_update(val, String(i))
            # if we received a trig, find and play a free voice
            if trig:
                free_voice = self.poly.find_voice_and_trigger(poly_objects, trig) # get the index of the free voice and trigger the PolyObject
                if free_voice != -1:
                    call_back(poly_objects[free_voice], val)

struct PolyGate(Movable, Copyable):
    """A Poly implementation that has an internal Messenger for handling messages from Python. The `next` function is designed to be used with list messages where the second value opens and closes the voice's gate.

    PolyGate is designed to be paired with the PolyPal class in Python. Give them the same name_space and num_messages arguments, and the messages sent from Python with PolyPal will be correctly received by the PolyGate object.
    """
    var poly: PolyTriggerSig
    var m: Messenger
    var num_messages: Int
    var world: World
    var string_dict: Dict[String, Int]
    var int_dict: Dict[Int, Int]
    

    def __init__(out self, initial_num_voices: Int, max_voices: Int, world: World, name_space: String, num_messages: Int = 10):
        self.poly = PolyTriggerSig(initial_num_voices=initial_num_voices, max_voices=max_voices)
        self.m = Messenger(world, name_space)
        self.num_messages = num_messages
        self.world = world
        self.string_dict = Dict[String, Int]()
        self.int_dict = Dict[Int, Int]()

    @doc_hidden
    def _reset[T: PolyObject](mut self, mut poly_objects: List[T]):
        if self.world[].top_of_block:
            for i in range(len(poly_objects)):
                self.poly.active_list[i] = poly_objects[i].check_active()
        else: 
            if self.world[].block_state == 1:
                for i in range(len(poly_objects)):
                    poly_objects[i].set_trigger(False)


    def next[
        T: PolyObject,
        call_back: def (mut poly_object: T, mut vals: List[Int]) capturing -> None
    ](
        mut self, 
        mut poly_objects: List[T]
    ):
        """This convenience function acheives all functionality of a Gated PolyObject synth in one function. It resets the Poly at the beginning of each block, looks for triggers from Python, and opens and closes gates for PolyObjects as needed. The call_back function is called whenever a new trigger is received from Python. `next` has to be paired with messages sent from Python as a List[Int] or a List[Float64], where the first value is the note or key to trigger and the second value is the velocity or gate of the note. A 0 in the second value will close the gate. The call_back function receives the List or value as the second argument, so the PolyObject can be controlled by the message from Python.
        """
        self._reset(poly_objects)
        if self.world[].top_of_block:
            vals = List[Int]()
            for i in range(self.num_messages):
                trig = self.m.notify_update(vals, String(i))
                if trig:
                    if vals[1] > 0: # if the velocity is greater than 0, trigger the note on
                        free_voice = self._find_voice_and_open_gate(poly_objects, trig, vals[0]) # get the index of the free voice
                        if free_voice != -1:
                            call_back(poly_objects[free_voice], vals)
                    else: # if the velocity is 0, trigger the note off for that note
                        # close the gate for the voice that is playing and forget that is was playing
                        freed_voice = self._close_gate(poly_objects, vals[0])
                        if freed_voice != -1:
                            call_back(poly_objects[freed_voice], vals)

    def next[
        T: PolyObject, 
        call_back: def(mut poly_object: T, mut vals: List[Float64]) capturing -> None
    ](
        mut self, 
        mut poly_objects: List[T]
    ):
        self._reset(poly_objects)
        
        if self.world[].top_of_block:
            # Explicit type variable instantiation using 'var'
            var vals = List[Float64]() 
            
            for i in range(self.num_messages):
                # Mojo 1.0 requires explicit var definitions for block scope bindings
                var trig = self.m.notify_update(vals, String(i)) 
                
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


    def _find_voice_and_open_gate[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool, key: String) -> Int:
        trigger_grain = self.poly._find_free_voice(poly_objects, trig)
        if trigger_grain != -1:
            self._open_gate(poly_objects, key, trigger_grain)
        return trigger_grain

    def _find_voice_and_open_gate[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool, key: Int) -> Int:
        trigger_grain = self.poly._find_free_voice(poly_objects, trig)
        if trigger_grain != -1:
            self._open_gate(poly_objects, key, trigger_grain)
        return trigger_grain

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

    @doc_hidden
    def _open_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: String, active_list_index: Int):
        poly_objects[active_list_index].set_gate(True)
        self.string_dict[key] = active_list_index
    
    @doc_hidden
    def _open_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: Int, active_list_index: Int):
        poly_objects[active_list_index].set_gate(True)
        self.int_dict[key] = active_list_index

struct PolyGateSig(Movable, Copyable):
    """A Poly object designed for managing polyphonic synths with gated controls that are signals."""
    var poly: PolyTriggerSig
    var changes: List[Changed[Bool]]
    var num_gates: Int
    var active_dict: Dict[Int, Int]

    def __init__(out self, initial_num_voices: Int, max_voices: Int, num_gates: Int):
        if initial_num_voices < num_gates:
            inv = num_gates
        else:
            inv = initial_num_voices
        self.poly = PolyTriggerSig(initial_num_voices=inv, max_voices=max_voices)
        self.changes = [Changed[Bool](False) for _ in range(num_gates)]
        self.num_gates = num_gates
        self.active_dict = Dict[Int, Int]()

    def next[T: PolyObject](mut self, mut poly_objects: List[T], gate_sigs: List[Bool]):
        """This function is designed to be used with polyphonic synths that have gated controls that are signals.

        Args:
            poly_objects: A list of structs conforming to the PolyObject trait. This function calls the set_gate function for each PolyObject to open and close the gates as needed.
            gate_sigs: A list of boolean signals that control the gates of the voices. Each signal corresponds to a different gate, so the length of the gate_sigs list should be the same as the number of gates in the synth. When a signal goes from False to True, the corresponding gate will be opened for a new voice. When a signal goes from True to False, the corresponding gate will be closed for the voice that is currently playing with that gate.
        """
        self.poly._reset(poly_objects)
        for i in range(len(gate_sigs)):
            changed = self.changes[i].next(gate_sigs[i])
            if changed:
                if gate_sigs[i]: # if the signal went from False to True, trigger the note on for that gate
                    _ = self._find_voice_and_open_gate(poly_objects, changed, Int(i))
                else:
                    _ = self._close_gate(poly_objects, Int(i))

    def _find_voice_and_open_gate[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool, key: Int) -> Int:
        trigger_grain = self.poly._find_free_voice(poly_objects, trig)
        if trigger_grain != -1:
            self._open_gate(poly_objects, key, trigger_grain)
        return trigger_grain

    @doc_hidden
    def _close_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: Int) -> Int:
        active_list_index = self.active_dict.pop(key, -1)
        if active_list_index != -1:
            poly_objects[active_list_index].set_gate(False)
        return active_list_index

    @doc_hidden
    def _open_gate[T: PolyObject](mut self, mut poly_objects: List[T], key: Int, active_list_index: Int):
        poly_objects[active_list_index].set_gate(True)
        self.active_dict[key] = active_list_index

struct PolyTriggerSig(Movable, Copyable):
    """A Poly implementation for synths triggered by signals, like TGrains and PitchShift.
    """
    var active_list: List[Bool]
    var max_voices: Int

    def __init__(out self, initial_num_voices: Int, max_voices: Int):
        """
        Args:
            initial_num_voices (Int): the number of voices to start with. This can be changed later by the Poly object itself if more voices need to be added.
            max_voices (Int): the maximum number of voices that can be allocated. Poly will not allocate more than this number of voices.
        """
        self.active_list = [False for _ in range(initial_num_voices)]
        self.max_voices = max_voices

    def next[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool) -> Int:
        """Looks at the value of trig. If trig is True, looks for a free voice and triggers it. Returns the index of the voice that was triggered, or -1 if no voice was triggered.
        """
        self._reset(poly_objects)
        return self.find_voice_and_trigger(poly_objects, trig)

    def next[T: PolyObject](mut self, 
        mut poly_objects: List[T], 
        trig: Bool, 
        call_back: def(mut poly_object: T, trig: Bool) capturing -> None
    ) -> Int:
        self._reset(poly_objects)
        voice_index = self.find_voice_and_trigger(poly_objects, trig)
        if voice_index != -1:
            call_back(poly_objects[voice_index], trig)
        return voice_index

    @doc_hidden
    def _reset[T: PolyObject](mut self, mut poly_objects: List[T]):
        """Must be called before any subsequent calls to find_voice_and_trigger or _find_voice_and_open_gate. This function resets the triggered state of all voices at the beginning of each block or every sample, depending on the only_top_of_block parameter.
        """
        for i in range(len(poly_objects)):
            self.active_list[i] = poly_objects[i].check_active()
            poly_objects[i].set_trigger(False)

    @doc_hidden
    def _find_free_voice[T: PolyObject](mut self, mut poly_objects: List[T], trig: Bool) -> Int:
        trigger_grain = -1
        if trig:
            list_len = len(self.active_list)
            trigger_grain, add_voice_bool = self._find_voice(list_len)
            if add_voice_bool:
                if list_len < self.max_voices:
                    self.active_list.append(True)
                    temp = poly_objects[0].copy() # copy the first voice
                    temp.reset_env() # reset the env of the new voice so that it doesn't just start playing when it's copied if the first voice is already active
                    temp.set_gate(False) 

                    poly_objects.append(temp^) 
                else:
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
