# Exporters

The exporters turn MMMAudio graphs, and single MMMAudio structs, into things that run
outside of MMMAudio:

| Exporter | What it makes |
|---|---|
| [PluginExporter](PluginExporter/README.md) | VST3, CLAP and AU plugins |
| [SCExporter](SCExporter/README.md) | SuperCollider UGens |
| [VCVExporter](VCVExporter/README.md) | VCV Rack modules |

All three compile the graph with Mojo and use the same engine interface,
`MMMAudioPluginBridge.mojo`, which is in `PluginExporter/src/`.

## Vibe coded and in beta

The exporters are vibe coded. We organized and documented the rest of MMMAudio with
great care. The exporters are different: LLMs wrote most of the code that connects
MMMAudio to the VST, CLAP, AU, SuperCollider and VCV Rack APIs, and it hasn't yet been
reviewed with the same care as the rest of the library.

The exporters are in beta:

- Expect bugs, rough edges and missing features.
- The options, the folder layout and what an export produces may change without
  warning.
- Most testing has been on macOS. Linux support is partial, and some of it is
  untested.
- Before you rely on an exported plugin, UGen or module in a performance or a release,
  test it well.

Bug reports and fixes are welcome.

## Layout

Each exporter has the same layout:

| | |
|---|---|
| `export_*.py` | The exporter, for the command line and for Python |
| `src/` | Templates, plus the SDKs and headers the exporter downloads on first use |
| `builds/` | One project per export |

Git ignores downloads, generated files and `builds/`.
