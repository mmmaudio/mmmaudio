from mmm_audio import *
# from std.random import random_si64

struct Tone(Movable,Copyable):
    var world: World
    var osc: Osc[]
    var freq: Float64
    var m: Messenger
    var gate: Bool

    def __init__(out self, world: World, namespace: String):
        self.world = world
        self.osc = Osc(self.world)
        self.freq = 440.0
        self.m = Messenger(self.world,namespace)
        self.gate = False

    def next(mut self) -> Float64:

        if self.m.notify_update("freq", self.freq) :
            print("Tone freq updated to ", self.freq)

        if self.m.notify_update("gate", self.gate) :
            print("Tone gate updated to ", self.gate)

        var sig = self.osc.next(self.freq) if self.gate else 0.0

        return sig

struct MessengerExample(Copyable, Movable):
    var world: World
    var m: Messenger
    var tones: List[Tone]
    
    var bool: Bool
    var bools: List[Bool]
    var float: Float64
    var floats: List[Float64]
    var int: Int
    var ints: List[Int]
    var string: String
    var strings: List[String]
    var counter: Float64

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)

        self.tones = List[Tone]()
        for i in range(2):
            self.tones.append(Tone(self.world, "tone_" + String(i)))

        self.bool = False
        self.bools = [False, False]
        self.float = 0.0
        self.floats = [0.0, 0.0]
        self.int = 0
        self.ints = [0, 0]
        self.string = ""
        self.strings = ["", ""]
        self.counter = 0
    
    def next(mut self) -> MFloat[2]:

        
        if self.m.notify_update("bool", self.bool) :
            print("Bool value is now: " + String(self.bool))

        if self.m.notify_update("float", self.float) :
            print("Float value is now: " + String(self.float))

        if self.m.notify_update("floats", self.floats) :
            print("Updated floats to ")
            for f in self.floats:
                print("  ", f)

        if self.m.notify_update("int", self.int) :
            print("Updated int to ", self.int)

        if self.m.notify_update("ints", self.ints) :
            print("Updated ints to:", end="")
            for i in self.ints:
                print("  ", i, end="")
            print("")

        if self.m.notify_update("string", self.string) :
            print("Updated string to ", self.string)

        if self.m.notify_update("strings", self.strings) :
            print("Updated strings to ")
            for s in self.strings:
                print("  ", s)

        if self.m.notify_trig("trig"):
            print("Received trig")

        
        def recv_floats(vals: List[Float64]) capturing -> None:
            for val in vals:
                self.floats.append(val)
            print("Appended the following floats to self.floats: ", vals, " self.floats is now holding: ", self.floats)

        self.m.address_callback[recv_floats]("callback")

        # Send a new message out every 2 seconds
        if self.counter % (self.world[].sample_rate * 2) == 0:
            self.m.send_floats("list_from_mojo", [random_float64(), random_float64()])
            
        # Send a new message out every 4 seconds
        if self.counter % (self.world[].sample_rate * 4) == 0:
            self.m.send_string("string_from_mojo", ["Hello World!", "nihao shijie", "My life for aiur"][random_si64(0,2)])
        
        self.counter += 1

        var out = MFloat[2](0.0, 0.0)
        for i in range(2):
            out[i] = self.tones[i].next()

        return out * dbamp(-20.0)
