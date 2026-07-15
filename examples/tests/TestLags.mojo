
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestLags(Movable, Copyable):
    var world: World
    var square: LFOsc[4]
    var lag: Lag[]
    var lag2: Lag[]
    var lag_ud: LagUD[]
    var lag_ud2: LagUD[]
    var lags: Lags[4]
    var lags_ud: LagsUD[4]

    def __init__(out self, world: World):
        self.world = world
        self.square = LFOsc[4](world)
        self.lag = Lag[](world, 0.1)
        self.lag2 = Lag[](world, 3.0)
        self.lag_ud = LagUD[](world, 0.1, 3.0)
        self.lag_ud2 = LagUD[](world, 3.0, 0.1)
        self.lags = Lags[4](world, 3.0)
        self.lags_ud = LagsUD[4](world, 0.1, 3.0)

    def next(mut self) -> MFloat[2]:
        sq = self.square.next[OscType.square](0.1)
        lag = self.lag.next(sq[0])
        lag2 = self.lag2.next(sq[0])
        lag_ud = self.lag_ud.next(sq[0])
        lag_ud2 = self.lag_ud2.next(sq[0])
        sqs = [sq[0], sq[1], sq[2], sq[3]]
        self.lags.next(sqs)
        for i in range(4):
            self.lags_ud[i] = self.lag_ud.next(sqs[i])
        self.lags_ud.next()

        self.world[].print("sq: ", sq, "lag: ", lag_ud, "lag2: ", lag_ud2, "lags_ud: ", self.lags_ud[0])#, "lag_ud: ", lag_ud, "lag_ud2: ", lag_ud2, "lags: ", self.lags[0], "lags_ud: ", self.lags_ud[0])

        return 0.0
