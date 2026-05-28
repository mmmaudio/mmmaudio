## UGens

- Shaper
- Dattorro, GVerb

## Big Ones

- replace pyaudio with Mojo PortAudio bindings
- ~~load and save wav files without numpy/scipy~~ working!
- ~~Multiple graphs in one MMMAudioinstance~~ not necessary with multiprocessor support
- ~~multiprocessor support~~ working!

## Outline of TableReading

* struct `Player` can play back anything that implements the `Playable` trait
    * `Player::next()`
    * `Player:: var prev_idx_f`
* The interpolation `fn`s are not owned by anything. They will live in `.functions`. They get called as `fn`s in `Player`
* trait `Playable`
  * `def __getitem__`
  * `def at_phase[interp: Interp = Interp.none]` for convenience re: windowing, etc.
* struct `Buffer` is for loading sound files and VWTs.
  * `var sample_rate`
* struct `OscBuffer` will hold wavetables 2^14 in size
* `BufferedProcess` will still make it's own windows to ensure they're the perfect size. Other UGens can of course do this as well.