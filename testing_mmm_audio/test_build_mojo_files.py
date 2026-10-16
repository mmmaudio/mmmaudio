from glob import glob
import os
from pathlib import Path
import subprocess
import tempfile

def test_dir(dirpath: str, skips: list[str] = []):
    mojo_files = glob(f"{dirpath}/*.mojo")
    for mojo_file in mojo_files:
        base = os.path.basename(mojo_file)
        if base in skips:
            print(f"Skipping {mojo_file}...")
            continue
        if base != "__init__.mojo":
            print(f"Running {mojo_file}...")
            subprocess.run(["mojo", "build", "--emit", "object", mojo_file], check=True)
            stem = Path(mojo_file).stem
            os.system(f"rm {stem}.o")

def test_package(dirpath: str):
    """Check that a package compiles, by precompiling the whole package to a temporary file.

    Package files can't be built one at a time (as `test_dir` does) because of import cycles.

    Args:
        dirpath: The package directory.
    """
    print(f"Precompiling {dirpath}...")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / f"{Path(dirpath).name}.mojoc"
        subprocess.run(["mojo", "precompile", dirpath, "-o", str(out)], check=True)

if __name__ == "__main__":
    test_package("mmm_audio")  # includes mmm_audio/ML
    test_dir("examples")
    test_dir("examples/ML_examples")
    test_dir("examples/tests")