"""Regress the duplicate-BOM delivery bug and require reproducible ZIP bytes."""
import codecs
import importlib.util
from pathlib import Path
import shutil
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location("recovery_builder", Path(__file__).with_name("Build-RecoveryPackage.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

with tempfile.TemporaryDirectory(prefix="stroked-package-test-") as tmp:
    tmp = Path(tmp)
    source = Path(__file__).parent / "local-website"
    copy = tmp / "source"
    shutil.copytree(source, copy)
    clean = builder.build(source, tmp / "clean.zip")
    for script in copy.glob("*.ps1"):
        script.write_bytes(codecs.BOM_UTF8 * 2 + script.read_bytes())
    repaired = builder.build(copy, tmp / "repaired.zip")
    assert clean == repaired, "Leading encoding markers changed final package bytes"
    with zipfile.ZipFile(tmp / "repaired.zip") as archive:
        assert archive.testzip() is None
        assert archive.namelist() == sorted(archive.namelist(), key=lambda n: (n.casefold(), n))
        for name in archive.namelist():
            if name.endswith(".ps1"):
                raw = archive.read(name)
                assert raw.startswith(codecs.BOM_UTF8)
                assert not raw[3:].startswith(codecs.BOM_UTF8), name
                assert b"\n" not in raw.replace(b"\r\n", b""), name
        vendor = f"{builder.ROOT_NAME}/vendor/supabase.min.js"
        assert archive.read(vendor) == (source / "vendor/supabase.min.js").read_bytes()
print("PASS: duplicate-BOM input produces identical ZIP bytes; vendor bytes preserved.")
