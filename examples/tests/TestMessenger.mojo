from mmm_audio import *

struct TestMessenger(Movable, Copyable):
    """Uses `Messenger.update`, `notify_update` and `address_callback` with every supported message type and prints what each receives."""
    var world: World
    var m: Messenger
    var f: Float64
    var i: Int
    var b: Bool
    var s: String
    var fs: List[Float64]
    var is_: List[Int]
    var bs: List[Bool]
    var ss: List[String]
    var stereo: MFloat[2]
    var quad: SIMD[DType.float32, 4]
    var f32: Float32

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)
        self.f = 0.0
        self.i = 0
        self.b = False
        self.s = String()
        self.fs = List[Float64]()
        self.is_ = List[Int]()
        self.bs = List[Bool]()
        self.ss = List[String]()
        self.stereo = MFloat[2](0.0, 0.0)
        self.quad = SIMD[DType.float32, 4](-1.0)
        self.f32 = 0.0

    def next(mut self) -> MFloat[2]:
        # update: no return value
        self.m.update("f", self.f)
        self.m.update("i", self.i)
        self.m.update("b", self.b)
        self.m.update("s", self.s)
        self.m.update("fs", self.fs)
        # notify_update: returns whether the value changed
        if self.m.notify_update("is", self.is_):
            print("update ints:", self.is_)
        if self.m.notify_update("bs", self.bs):
            print("update bools:", self.bs)
        if self.m.notify_update("ss", self.ss):
            print("update strings:", self.ss)
        if self.m.notify_update("stereo", self.stereo):
            print("update MFloat[2]:", self.stereo)
        if self.m.notify_update("quad", self.quad):
            print("update SIMD[float32, 4]:", self.quad)
        if self.m.notify_update("f32", self.f32):
            print("update Float32:", self.f32)

        def on_float(v: Float64) capturing -> None:
            print("float callback:", v)
        def on_int(v: Int) capturing -> None:
            print("int callback:", v)
        def on_bool(v: Bool) capturing -> None:
            print("bool callback:", v)
        def on_string(v: String) capturing -> None:
            print("string callback:", v)
        def on_floats(v: List[Float64]) capturing -> None:
            print("floats callback:", v)
        def on_ints(v: List[Int]) capturing -> None:
            print("ints callback:", v)
        def on_bools(v: List[Bool]) capturing -> None:
            print("bools callback:", v)
        def on_strings(v: List[String]) capturing -> None:
            print("strings callback:", v)

        self.m.address_callback[on_float]("cb_float")
        self.m.address_callback[on_int]("cb_int")
        self.m.address_callback[on_bool]("cb_bool")
        self.m.address_callback[on_string]("cb_string")
        self.m.address_callback[on_floats]("cb_floats")
        self.m.address_callback[on_ints]("cb_ints")
        self.m.address_callback[on_bools]("cb_bools")
        if self.m.notify_address_callback[on_strings]("cb_strings"):
            print("notify_address_callback returned True for cb_strings")

        if self.m.notify_trig("report"):
            print("update float:", self.f, " int:", self.i, " bool:", self.b, " string:", self.s, " floats:", self.fs)

        return MFloat[2](0.0, 0.0)
