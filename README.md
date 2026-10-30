
<p align="left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="resources/LogoDark.jpg">
    <source media="(prefers-color-scheme: light)" srcset="resources/LogoWhite.jpg">
    <img alt="Project Logo" src="resources/LogoDark.jpg" width="300">
  </picture>
</p>

MMMAudio is a Mojo/Python environment for sound synthesis which uses Mojo for real-time audio processing and Python as a scripting control language. It runs on Mac and Linux, including Raspberry Pi (on Ubuntu). It kind of works on Windows through wsl.

MMMAudio is a highly efficient synthesis system that uses parallelized SIMD operations for maximum efficiency on CPUs. 

Writing dsp code in Mojo is straight-forward and the feedback loop of being able to quickly compile the entire project in a few seconds to test is faster than making externals in SC/max/pd. 

Its design foregrounds four strengths that we feel set it apart from existing Computer Music Environments: 
1) It unifies instrument building and DSP authoring under the same workflow and language (Modular's Mojo), letting creators prototype innovative DSP directly within the same environment where they are building instruments.
2) It allows (and encourages) single sample feedback and oversampling anywhere in the DSP graph.
3) It leverages the existing, well supported programming languages, Mojo and Python, as well as their infrastructure, taking advantage of the many packages in the Python ecosystem. 
4) It embraces industry-leading and foundation-supported AI and analysis tools, connecting to Python and Mojo's mature ML ecosystems like PyTorch and scikit-learn.

## Getting Started

[See the Getting Started guide](https://mmmaudio.github.io/mmmaudio/getting_started/).

## A Note for Users who are updating MMMAudio with `git pull`

The repo now includes a `.vscode/settings.json` with all the settings MMMAudio needs.

If you made your own `.vscode/settings.json` before it was included in the repo, `git pull` will stop with "untracked working tree files would be overwritten". Either run `git stash` to reset any changes you have made to the repo or delete or move your copy of `.vscode/settings.json` and pull again.

## Documentation

A link to the online documentation is found here: [https://mmmaudio.github.io/mmmaudio/](https://mmmaudio.github.io/mmmaudio/)

## Forum

Join the [MMMAudio Discourse Group](https://mmmaudio.discourse.group/). Ask questions and give feedback!

## Credits

Created by Sam Pluta and Ted Moore.

This repository includes a recording of "Shiverer" by Eric Wubbels as the default sample. This was performed by Eric Wubbels and Erin Lesser and recorded by Jeff Snyder.

## Citing MMMAudio

The best way to cite this work is the [paper](https://github.com/mmmaudio/mmmaudio/blob/main/resources/MMMAudioPaperICMC2026.pdf) that was presented at the 2026 International Computer Music Conference.

```bibtex
@inproceedings{pluta2026mmmaudio,
  title={The MMMAudio Computer Music Environment},
  author={Pluta, Sam and Moore, Ted},
  booktitle={Proceedings of the International Computer Music Conference (ICMC)},
  year=2026
}
```
