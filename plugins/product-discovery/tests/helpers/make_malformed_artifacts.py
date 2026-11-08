import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
target = pathlib.Path(sys.argv[2])
_front, tail = source.split("---\n", 1)[1].split("\n---\n", 1)
(target / "malformed.md").write_text(
    source.replace("schema_version: product-artifact/1", "schema_version: [", 1)
)
(target / "scalar.md").write_text("---\nnot-a-mapping\n---\n" + tail)
