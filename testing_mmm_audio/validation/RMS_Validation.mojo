"""RMS Unit Test"""

from mmm_audio import *

comptime windowsize: Int = 1024
comptime hopsize: Int = 512

struct Analyzer(BufferedProcessable):
    var world: World
    var rms_values: List[Float64]

    def __init__(out self, world: World):
        self.world = world
        self.rms_values = List[Float64]()

    def next_window(mut self, mut buffer: List[Float64]):
        val = RMS.from_window(buffer)
        self.rms_values.append(val)
        return

def main():
    world_info = alloc[WorldInfo](1)
    world_info.init_pointee_move(WorldInfo())
    
    w = alloc[MMMWorld](1)
    w.init_pointee_move(MMMWorld(44100, world_info))

    buffer = Buffer.load("resources/Shiverer.wav")
    playBuf = Play(w)

    analyzer = BufferedProcess[Analyzer,False,WindowType.rect,WindowType.rect](w, Analyzer(w), window_size=windowsize, hop_size=hopsize)

    for _ in range(buffer.num_frames):
        sample = playBuf.next(buffer)
        _ = analyzer.next(sample)
    
    pth = "testing_mmm_audio/validation/mojo_results/rms_mojo_results.csv"
    try:
        with open(pth, "w") as f:
            f.write("windowsize,",windowsize,"\n")
            f.write("hopsize,",hopsize,"\n")
            f.write("RMS\n")
            for i in range(len(analyzer.process.rms_values)):
                f.write(String(analyzer.process.rms_values[i]) + "\n")
        print("Wrote results to ", pth)
    except err:
        print("Error writing to file: ", err)
