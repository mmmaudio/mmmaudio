"""Generate MMMAudio onset detection-function and onset-slice validation data."""

from std.sys import argv

from mmm_audio import *
from std.memory.alloc import unsafe_alloc

def default_audio_path() -> String:
    return "/Users/ted/dev/flucoma-core/Resources/AudioFiles/Nicol-LoopE-M.wav"

def resolve_audio_path() raises -> String:
    var args = argv()
    var i = 0
    while i < len(args):
        if args[i] == "--audio-path":
            if i + 1 >= len(args):
                raise Error("--audio-path requires a value")
            return args[i + 1]
        i += 1

    return default_audio_path()

def main() raises:

    var window_size = 1024
    var hop_size = 512

    var thresholds = List[Float64](length=10,fill=0.0)

    with open("testing_mmm_audio/validation/flucoma_sc_results/onset_detection_flucoma_thresholds.csv", "r") as f:
        var thresholds_str = f.read().split(",")
        for i, ts in enumerate(thresholds_str):
            thresholds[i] = Float64(ts)

    var audio_path = resolve_audio_path()
    var buf = Buffer.load(audio_path)
    var sample_rate = buf.sample_rate

    comptime filter_size: Int = 5
    comptime frame_delta: Int = 0
    var onset_min_slice_len: Float64 = (Float64(hop_size) / sample_rate) * 2.0

    var environment = unsafe_alloc[Environment](1)
    environment.unsafe_write(Environment(64, 2, 2))
    var world = unsafe_alloc[MMMWorld](1)
    world.unsafe_write(MMMWorld(sample_rate, environment))

    var buf_detection_points = List[List[Int]](length=10, fill=List[Int]())

    for i in range(10):
        var onset_threshold = thresholds[i]
        
        var onset_slice = OnsetDetection.buf_analysis(
            world,
            buf,
            metric=OnsetMetric(i),
            threshold=onset_threshold,
            min_slice_len=onset_min_slice_len,
            window_size=window_size,
            hop_size=hop_size,
            filter_size=filter_size,
            frame_delta=frame_delta,
        )

        print("metric: ", i, ", threshold: ", onset_threshold, ", onsets: ", len(onset_slice))
        buf_detection_points[i] = onset_slice^

    with open("testing_mmm_audio/validation/mojo_results/mojo_buf_onset_detection_points.csv", "w") as f:
        for i in range(10):
            var slice_str = ",".join([String(x) for x in buf_detection_points[i]])
            if(i != 0):
                f.write("\n")
            f.write(slice_str)

    var rt_detection_points = List[List[Int]](length=10, fill=List[Int]())
    for i in range(10):
        var rt_slicer = OnsetDetection(world, metric=OnsetMetric(i), threshold=thresholds[i], min_slice_len=onset_min_slice_len, window_size=window_size, hop_size=hop_size, filter_size=filter_size, frame_delta=frame_delta)
        for sample_i in range(buf.num_frames):
            if rt_slicer.next(buf.data[0][sample_i]):
                rt_detection_points[i].append(sample_i)
    
    with open("testing_mmm_audio/validation/mojo_results/mojo_rt_onset_detection_points.csv", "w") as f:
        for i in range(10):
            var slice_str = ",".join([String(x) for x in rt_detection_points[i]])
            if(i != 0):
                f.write("\n")
            f.write(slice_str)

    var odf_buf_time_series = List[List[Float64]](length=10, fill=List[Float64]())

    # test onset detection feature
    for i in range(10):
        var time_series = OnsetDetectionFeature.buf_analysis(
            buf=buf, 
            chan=0, 
            start_frame=0, 
            num_frames=-1, 
            metric=OnsetMetric(i), 
            window_size=window_size, 
            hop_size=hop_size)
        
        for sample in time_series:
            odf_buf_time_series[i].append(sample[0])

    with open("testing_mmm_audio/validation/mojo_results/mojo_buf_odf_time_series.csv", "w") as f:
        for i in range(10):
            var time_series_str = ",".join([String(x) for x in odf_buf_time_series[i]])
            if(i != 0):
                f.write("\n")
            f.write(time_series_str)

