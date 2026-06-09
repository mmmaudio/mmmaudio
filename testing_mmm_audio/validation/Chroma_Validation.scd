var dir = thisProcess.nowExecutingPath.dirname;
s.options.sampleRate = 44100;
s.waitForBoot{

	var windowsize = 1024;
	var hopsize = 512;

	"windowsize: %".format(windowsize).postln;
	"hopsize: %".format(hopsize).postln;

	b = Buffer.readChannel(s,dir+/+"../../resources/Shiverer.wav",channels:[0]);
	f = Buffer(s);
	s.sync;
	FluidBufChroma.processBlocking(
		server: s,
		source: b,
		features: f,
		windowSize: windowsize,
		hopSize: hopsize,
		padding: 0,
		normalize:1,
		ref:60.midicps

	);
	s.sync;
	f.loadToFloatArray(action:{
		arg fa;
		var file = File.open(dir+/+"flucoma_sc_results/chroma_flucoma_results.csv","w");
		fa = fa.clump(12);
		fa.do{
			arg row, i;
			if(i > 0){ file.write("\n") };
			row.do{
				arg val, j;
				if(j > 0){ file.write(",") };
				file.write(val.asString);
			}
		};
		file.close;
	});

	s.quit;

	0.exit;
};
