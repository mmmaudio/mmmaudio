"""Generate Markdown documentation from Mojo source files.

This script recursively scans a directory for `.mojo` files, executes
`mojo doc <file.mojo>` to obtain structured JSON documentation, renders that
JSON through a Jinja2 Markdown template, and writes the resulting `.md` files
to an output directory while mirroring the original source tree structure.

Compared to the earlier JSON batch mode, this version avoids intermediate
JSON artifacts on disk and always reflects the current state of the source.

Exit status: 0 on full success, 1 if any file fails to document.
"""

from jinja2 import Template
import json
import argparse
import sys
import shutil
import subprocess
from pathlib import Path
from typing import Dict, Any, List

from jinja2 import Environment, FileSystemLoader, TemplateNotFound
try:
    # MkDocs provides a Nav object at runtime; only type hint if available
    from mkdocs.config.defaults import MkDocsConfig  # type: ignore
except Exception:  # pragma: no cover - optional import
    MkDocsConfig = Any  # type: ignore

# ---------------- Hard‑coded whitelist of source directories ----------------
# These are relative to the repository root (one level above this script's dir).
REPO_ROOT = Path(__file__).resolve().parent.parent
HARDCODED_SOURCE_DIRS = [
    "mmm_audio",
    "mmm_python"
    # Add/remove directory names here as needed
]

TEMPLATES_DIR = REPO_ROOT / 'doc_generation' / 'templates'

_env: Environment | None = None

def process_python_sources(output_dir: Path):
    py_out = output_dir / 'api'
    py_out.mkdir(parents=True, exist_ok=True)
    for rel_dir in HARDCODED_SOURCE_DIRS:
        src_dir = REPO_ROOT / rel_dir
        for py in src_dir.rglob('*.py'):
            if py.name == '__init__.py':
                continue
            # Module import path relative to repo root
            module_path = py.relative_to(REPO_ROOT).with_suffix('')
            dotted = '.'.join(module_path.parts)
            md_path = py_out / (py.stem + '.md')
            md_path.parent.mkdir(parents=True, exist_ok=True)
            md_path.write_text(f"# {py.stem}\n\n::: {dotted}\n", encoding='utf-8')
            
def get_jinja_env() -> Environment:
    global _env
    if _env is None:
        _env = Environment(
            loader=FileSystemLoader(str(TEMPLATES_DIR)),
            autoescape=False,
            trim_blocks=True,
            lstrip_blocks=True,
        )
    return _env

def render_template(template_name: str, context: dict) -> str:
    env = get_jinja_env()
    try:
        tmpl = env.get_template(template_name)
    except TemplateNotFound:
        raise RuntimeError(f"Template '{template_name}' not found in {TEMPLATES_DIR}")
    return tmpl.render(**context)

def find_mojo_files(root: Path) -> List[Path]:
    """Return a list of all .mojo files under root (recursively)."""
    return [p for p in root.rglob("*.mojo") if p.is_file()]

def collect_whitelisted_mojo_files() -> List[Path]:
    """Gather .mojo files only from the hard-coded whitelisted directories."""
    files: List[Path] = []
    seen = set()
    for rel_dir in HARDCODED_SOURCE_DIRS:
        dir_path = REPO_ROOT / rel_dir
        if not dir_path.exists() or not dir_path.is_dir():
            continue
        for f in find_mojo_files(dir_path):
            if f not in seen:
                files.append(f)
                seen.add(f)
    return files

def run_mojo_doc(file_path: Path, json_output_dir: Path, timeout: int = 30) -> Dict[str, Any]:
    """Execute `mojo doc <file>` and return parsed JSON.
    
    The JSON output is written to a file in json_output_dir for inspection,
    then loaded and returned as a dictionary.

    Raises RuntimeError on non-zero exit or JSON parse error.
    """
    # Create JSON output filename based on the source file path
    json_filename = file_path.stem + ".json"
    json_output_path = json_output_dir / json_filename
    
    # Ensure the output directory exists
    json_output_dir.mkdir(parents=True, exist_ok=True)
    
    cmd = ["mojo", "doc", "-o", str(json_output_path), str(file_path)]
    try:
        completed = subprocess.run(
            cmd,
            # capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        raise RuntimeError("Mojo binary not found.")
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"Timeout executing: {' '.join(cmd)}")

    if completed.returncode != 0:
        raise RuntimeError(
            f"mojo doc failed for {file_path} (exit {completed.returncode}):\nSTDERR:\n{completed.stderr.strip()}\nSTDOUT:\n{completed.stdout.strip()}"
        )

    # Load JSON from the output file
    try:
        with open(json_output_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"JSON output file not found: {json_output_path}")
    except json.JSONDecodeError as e:
        # Read first part of the file for diagnostics
        try:
            with open(json_output_path, 'r', encoding='utf-8') as f:
                snippet = f.read(400)
        except Exception:
            snippet = "<unable to read file>"
        raise RuntimeError(f"Invalid JSON in output file {json_output_path}: {e}\nFile snippet:\n{snippet}")

def clean_mojo_doc_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Remove unwanted functions and scrub overload metadata."""

    skipped_names = {"__repr__", "copy", "__copyinit__", "__moveinit__"}

    def _clean_functions(functions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        cleaned: List[Dict[str, Any]] = []
        for func in functions:
            if func.get('name') in skipped_names:
                continue
            for overload in func.get('overloads', []):
                args = overload.get('args', [])
                overload['args'] = [a for a in args if a.get('name') != 'self']
                params = overload.get('parameters')
                if isinstance(params, list):
                    overload['parameters'] = [p for p in params if p.get('name') != 'self']
            cleaned.append(func)
        return cleaned

    decl = data.get('decl', {})
    for struct in decl.get('structs', []):
        struct['functions'] = _clean_functions(struct.get('functions', []))

    for trait in decl.get('traits', []):
        trait['functions'] = _clean_functions(trait.get('functions', []))

    return data

def add_guide_text(data: Dict[str, Any]) -> Dict[str, Any]:
    guides_dir = REPO_ROOT / 'doc_generation' / 'static_docs' / 'guides'
    if not guides_dir.exists() or not guides_dir.is_dir():
        return data

    decl = data.get('decl', {})
    for struct in decl.get('structs', []):
        name = struct.get('name')
        if not name:
            continue
        guide_path = guides_dir / f"{name}.md"
        if guide_path.exists() and guide_path.is_file():
            try:
                struct['guide'] = guide_path.read_text(encoding='utf-8')
            except Exception:
                # If a guide cannot be read, skip adding it so generation continues.
                continue

    for trait in decl.get('traits', []):
        name = trait.get('name')
        if not name:
            continue
        guide_path = guides_dir / f"{name}.md"
        if guide_path.exists() and guide_path.is_file():
            try:
                trait['guide'] = guide_path.read_text(encoding='utf-8')
            except Exception:
                continue
    return data

def process_mojo_sources(input_dir: Path, output_dir: Path, verbose: bool=False) -> bool:
    """Process all Mojo source files under input_dir and emit markdown into output_dir.

    Returns True if all files processed successfully.
    """
    if not input_dir.exists():
        print(f"Error: Input directory '{input_dir}' does not exist")
        return False
    if not input_dir.is_dir():
        print(f"Error: '{input_dir}' is not a directory")
        return False

    # Create JSON output directory for inspection
    json_output_dir = output_dir.parent / 'json_output'

    # Only collect mojo files from directories that contain source files, 
    # specified in the variable HARDCODED_SOURCE_DIRS. This avoids grabbing 
    # Mojo files from the examples directory (not source code) or other various places.
    mojo_files = collect_whitelisted_mojo_files()
    
    if not mojo_files:
        print(f"Warning: No .mojo files found in '{input_dir}'")
        return True

    processed = 0
    errors = 0

    for src_file in mojo_files:
        if src_file.stem == '__init__' or src_file.stem == 'MMMGraph_solo':
            continue
        rel_path = Path(src_file.name)
        rel_path = rel_path.with_name(rel_path.stem.replace("_Module", ""))  # Clean up module suffixes
        # Mirror directory and replace suffix
        out_file = output_dir / rel_path.with_suffix('.md')
        out_file.parent.mkdir(parents=True, exist_ok=True)
        try:
            data = run_mojo_doc(src_file, json_output_dir)
            data = clean_mojo_doc_data(data)
            data = add_guide_text(data)
            rendered = render_template('mojo_doc_template_jinja.md', data)
            out_file.write_text(rendered, encoding='utf-8')
            processed += 1
        except Exception as e:
            errors += 1
            print(f"  Error: {e}")

    return errors == 0

def process_example_file(python_example_file_path: Path):
    if not python_example_file_path.exists() or not python_example_file_path.is_file():
        print(f"Error: Example file '{python_example_file_path}' does not exist or is not a file, skipping.")
        return

    mojo_example_file = python_example_file_path.stem + '.mojo'
    # Path of the example's folder relative to the repo root, e.g. "examples" or "examples/ML_examples"
    example_rel_dir = python_example_file_path.parent.relative_to(REPO_ROOT).as_posix()

    python_file_stem = python_example_file_path.stem  # filename without suffix
    output_md_path = REPO_ROOT / 'doc_generation' / 'docs_md' / 'examples' / f"{python_file_stem}.md"
    output_md_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with open(python_example_file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading example file '{python_example_file_path}': {e}")
        return
    
    # Find the code, which is after the docstring, if there is a docstring
    code_start = 0
    code_end = len(lines)
    in_docstring = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('"""') or stripped.startswith("'''"):
            if in_docstring:
                # End of docstring
                code_start = i + 1
                break
            else:
                # Start of docstring
                in_docstring = True
                if stripped.count('"""') == 2 or stripped.count("'''") == 2:
                    # Docstring starts and ends on the same line
                    in_docstring = False
                    code_start = i + 1
        elif in_docstring and (stripped.endswith('"""') or stripped.endswith("'''")):
            # End of multi-line docstring
            in_docstring = False
            code_start = i + 1
            break
        elif not in_docstring and stripped and not stripped.startswith('#'):
            # First non-comment, non-blank line outside docstring
            code_start = i
            break
        
    code = ''.join(lines[code_start:code_end]).rstrip()
    
    context = {
        'python_file_stem': python_file_stem,
        'example_rel_dir': example_rel_dir,
        'example_module': example_rel_dir.replace('/', '.') + '.' + python_file_stem,
        'mojo_file_name': mojo_example_file,
        'example_name': python_file_stem,
        'code': code,
    }
    
    tosc_file = python_example_file_path.with_suffix('.tosc')
    if tosc_file.exists() and tosc_file.is_file():
        context['tosc'] = tosc_file.name

    rendered = render_template('example_python_and_mojo_jinja.md', context)
    output_md_path.write_text(rendered, encoding='utf-8')

# Example folders (relative to examples/) to include in the docs, mapped to their nav section title.
# "" is the top level examples folder, whose pages go directly in the Examples nav.
EXAMPLE_SUBDIRS = {'': None, 'ML_examples': 'ML Examples'}

def process_examples_dir():
    example_files_src_dir = REPO_ROOT / 'examples'
    if not example_files_src_dir.exists() or not example_files_src_dir.is_dir():
        print(f"Error Examples directory '{example_files_src_dir}' does not exist or is not a directory, skipping examples processing.")
        return

    example_file_paths = []
    for subdir in EXAMPLE_SUBDIRS:
        example_file_paths += list((example_files_src_dir / subdir).glob('*.py'))
    
    for python_example_file_path in example_file_paths:
        if python_example_file_path.name == '__init__.py':
            continue
        process_example_file(python_example_file_path)

def build_examples_nav_entries() -> list[dict[str, str]]:
    """Scan examples directory and build list of nav mappings for Examples section.

    Returns a list like: [{'Overview': 'examples/index.md'}, {'Default Graph': 'examples/Default_Graph.md'}, ...]
    Assumes that the corresponding generated markdown files already exist (or will exist) in docs_md/examples.
    """
    example_dir = REPO_ROOT / 'examples'
    entries: list[dict[str, str]] = []
    # Always keep Overview first if it exists (static doc copied from static_docs/examples/index.md or generated manually)
    overview_md = Path('examples/index.md')
    if (REPO_ROOT / 'doc_generation' / 'docs_md' / overview_md).exists() or True:
        entries.append({'Overview': str(overview_md)})

    for subdir in EXAMPLE_SUBDIRS:
        py_files = sorted(p for p in (example_dir / subdir).glob('*.py') if p.name not in {'__init__.py'})
        # All example pages are generated flat into docs_md/examples, subdirectories only group the nav
        sub_entries = [{py.stem: f'examples/{py.stem}.md'} for py in py_files]
        if subdir:
            entries.append({EXAMPLE_SUBDIRS[subdir]: sub_entries})
        else:
            entries += sub_entries
    return entries

def update_examples_nav(config: MkDocsConfig):  # type: ignore
    """Mutate config.nav to replace the Examples section with dynamically built entries.

    If no Examples section is found, one is appended at the end.
    """
    if not hasattr(config, 'nav') or config.nav is None:
        return
    new_examples = build_examples_nav_entries()
    # config.nav is a list of dict/sections
    nav_list = config.nav
    inserted = False
    for i, item in enumerate(nav_list):
        if isinstance(item, dict) and 'Examples' in item:
            nav_list[i] = {'Examples': new_examples}
            inserted = True
            break
    if not inserted:
        nav_list.append({'Examples': new_examples})
    config.nav = nav_list
    print(f"[MkDocs Hook] Examples nav updated with {len(new_examples)-1} example pages.")

def copy_static_docs(output_dir: Path, args):
    # Hardcode the static doc entries to copy. Use paths relative to
    # doc_generation/static_docs (e.g., "guides", "index.md", "examples/foo.md").
    ALLOWED_STATIC_DOCS: list[str] = [
        "api",
        "contributing",
        "examples",
        "getting_started",
        "index.md"
    ]

    static_docs_src = Path('doc_generation/static_docs')
    if static_docs_src.exists() and static_docs_src.is_dir():
        try:
            if ALLOWED_STATIC_DOCS:
                iterable = []
                for rel in ALLOWED_STATIC_DOCS:
                    src_item = static_docs_src / rel
                    if not src_item.exists():
                        if args.verbose:
                            print(f"Warning: static doc path '{rel}' not found under {static_docs_src}, skipping.")
                        continue
                    iterable.append(src_item)
            else:
                iterable = list(static_docs_src.iterdir())

            for item in iterable:
                dest = output_dir / item.relative_to(static_docs_src)
                if item.is_dir():
                    shutil.copytree(item, dest, dirs_exist_ok=True)
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, dest)
        except Exception as e:
            print(f"Error copying static docs contents: {e}")
            sys.exit(1)
    else:
        if args.verbose:
            print(f"Error No static docs directory at {static_docs_src}, skipping static content copy.")

def clean_output_dir(output_dir: Path, args):
    try:
        for child in output_dir.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            else:
                try:
                    child.unlink()
                except FileNotFoundError:
                    continue
        # ensure directory still exists
        output_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:  
        print(f"Error cleaning contents of output directory: {e}")
        sys.exit(1)

def generate_docs_hook(config=None):
    """MkDocs hook entry point - generates docs with default settings (on_pre_build compatibility)."""
    
    # Repo root directory
    input_dir = Path('.').resolve()
    
    # Where all the generated markdown goes so that later mkdocs can pick it up
    output_dir = Path('./doc_generation/docs_md').resolve()
    
    print(f"[MkDocs Hook] Generating docs from {input_dir} to {output_dir}")
    
    # If it exists, clear ./doc_generation/docs_md so that there isn't any stale content lingering 
    if output_dir.exists():
        clean_output_dir(output_dir, type('args', (), {'verbose': False})())

    output_dir.mkdir(parents=True, exist_ok=True)

    # Copy ONLY the *contents* of static_docs into output_dir (not the directory itself)
    copy_static_docs(output_dir, type('args', (), {'verbose': True})())
        
    # use `mojo doc` to generate json files from Mojo source files
    # (however the json files are never actually saved to disk, the json string is 
    # passed to standard out and caught in Python to then be turned into a dict) 
    # and then use the json to render to markdown
    success = process_mojo_sources(
        input_dir=input_dir,
        output_dir=output_dir / 'api', # Place generated API docs under 'api' subdir
        verbose=True,
    )

    # Process all examples in the examples directory
    process_examples_dir()
    process_python_sources(output_dir)

    if not success:
        print("[MkDocs Hook] Documentation generation failed")

def configure_and_generate(config: MkDocsConfig):  # type: ignore
    """Combined on_config hook: generate docs early then inject dynamic Examples nav.

    MkDocs calls on_config before nav is finalized; we can mutate config.nav safely here.
    """
    print("[MkDocs Hook] on_config: generating docs and building dynamic Examples nav")
    # Run generation routine so example markdown exists before nav build
    generate_docs_hook(config)
    try:
        update_examples_nav(config)
    except Exception as e:
        print(f"[MkDocs Hook] Failed to update Examples nav dynamically: {e}")
    return config

def main(config=None):
    """CLI entry point or MkDocs hook."""
    # If called as a hook (config passed), run the hook function
    if config is not None:
        generate_docs_hook(config)
        return config
    
    # If not called as a hook, parse CLI arguments and run:
    
    parser = argparse.ArgumentParser(
        description="Recursively generate Markdown from Mojo source using `mojo doc` and a Jinja2 template.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -i ./mmm_audio -o ./docs/api/mojo
  %(prog)s --input-dir ./ --output-dir ./docs/api/mojo --template doc_generation/templates/mojo_doc_template_jinja.md
  %(prog)s -i mmm_audio -o docs/api/mojo -b /opt/mojo/bin/mojo -v
        """
    )

    parser.add_argument(
        '-i', '--input-dir',
        type=str,
        default='.',
        required=False,
        help='Root directory containing Mojo source files (recursively scanned)'
    )
    parser.add_argument(
        '-o', '--output-dir',
        type=str,
        default='./doc_generation/docs_md',
        required=False,
        help='Root directory where rendered Markdown will be written (mirrors source tree)'
    )
    parser.add_argument(
        '--clean', type=bool, default=True,
        help='Delete the entire output directory before generation (default: True)'
    )
    parser.add_argument(
        '-v', '--verbose', action='store_true', help='Enable verbose output'
    )

    args = parser.parse_args()

    input_dir = Path(args.input_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    if args.clean and output_dir.exists():
        clean_output_dir(output_dir, args)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Copy ONLY the contents of static_docs_src into output_dir (not the directory itself)
    copy_static_docs(output_dir, args)
        
    success = process_mojo_sources(
        input_dir=input_dir,
        output_dir=output_dir / 'api', # Place generated API docs under 'api' subdir
        verbose=args.verbose,
    )

    process_examples_dir()

    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()