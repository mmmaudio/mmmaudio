
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestEnv(Movable, Copyable):
    var world: World
    var envs: List[Env]
    var asr_env: ASREnv
    var line: Line[1]
    var messenger: Messenger
    var impulse: Impulse[]
    var mul: Float64

    var env_buffer: SIMDBuffer[1]

    def __init__(out self, world: World):
        self.world = world
        self.envs = [Env(self.world) for _ in range(3)]
        for i in range(3):
            self.envs[i].params = EnvParams([0, 1.0, 0.5, 0.5, 0.0], [0.01538462, 0.01538462, 0.00769231, 0.06153846], [0], True)
        
        self.asr_env = ASREnv(self.world)
        self.line = Line(self.world)
        self.messenger = Messenger(self.world)
        self.impulse = Impulse(self.world)
        self.mul = 0.1

        self.env_buffer = Env.get_env_buffer[win_type = WindowType.hann](self.world, 1024, self.envs[0].params)
        print(len(self.env_buffer.data))

    def next(mut self) -> MFloat[8]:
        line = self.line.next(0, 1.0, 0.1)
        env0 = self.envs[0].next(True, line)
        env1 = self.envs[1].next[win_type = WindowType.hann](True, line)
        env2 = self.envs[2].next[win_type = WindowType.sine](True, line)
        env3 = win_env[WindowType.blackman, Interp.linear](self.world, line)
        env4 = min_env[WindowType.hann](self.world, line, 0.3)
        gate = line < 0.8
        env5 = self.asr_env.next[WindowType.kaiser](0.025, 1., 0.025, gate, line)
        
        env6 = buf_env(self.world, self.env_buffer, line)

        return MFloat[8](env6, env1, env3, env4, env5, 0., 0., 0.) * 0.9



        