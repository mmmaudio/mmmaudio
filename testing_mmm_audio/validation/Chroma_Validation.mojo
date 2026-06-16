from mmm_audio import *

comptime fftsize: Int = 1024
comptime hopsize: Int = 512
comptime n_chroma: Int = 12

struct ChromaTestSuite(FFTProcessable):
	var chroma: Chroma
	var data: List[List[Float64]]

	def __init__(out self, w: World):
		self.chroma = Chroma[](w[].sample_rate, fftsize, n_chroma=n_chroma)
		self.data = List[List[Float64]]()

	def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]):
		self.chroma.next_frame(mags, phases)
		self.data.append(self.chroma.chroma.copy())

def main() raises:
	buf = Buffer.load("resources/Shiverer.wav")
	
	world_info = alloc[WorldInfo](1)
	world_info.init_pointee_move(WorldInfo())

	w = alloc[MMMWorld](1)
	w.init_pointee_move(MMMWorld(buf.sample_rate, world_info))

	chroma_ts = ChromaTestSuite(w)
	fftprocess = FFTProcess[ChromaTestSuite,False,WindowType.hann](w, chroma_ts^, window_size=fftsize, hop_size=hopsize)

	for i in range(buf.num_frames):
		_ = fftprocess.next(buf.data[0][i])

	print("Number of frames processed: ", len(fftprocess.buffered_process.process.process.data))

	with open("testing_mmm_audio/validation/mojo_results/chroma_mojo_results.csv", "w") as f:
		f.write("windowsize," + String(fftsize) + "\n")
		f.write("hopsize," + String(hopsize) + "\n")
		f.write("n_chroma," + String(n_chroma) + "\n")
		f.write("Chroma\n")
		for i, frame in enumerate(fftprocess.buffered_process.process.process.data):
			if i > 0:
				f.write("\n")
			for j, value in enumerate(frame):
				if j > 0:
					f.write(",")
				f.write(String(value))
