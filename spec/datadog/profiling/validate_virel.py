import contextlib
import io
from pathlib import Path
import struct
import sys


sys.path.insert(0, str(Path(sys.argv[1]) / "validators"))
from tcf_reader import Cursor, Reader


data = Path(sys.argv[2]).read_bytes()
chunks = []
offset = 0
while offset < len(data):
    size = struct.unpack_from(">Q", data, offset + 8)[0]
    assert 76 <= size <= len(data) - offset
    chunk = data[offset:offset + size]
    reader = Reader()
    reader.record = True
    with contextlib.redirect_stdout(io.StringIO()):
        reader.run(chunk)
    assert reader.chunks == 1 and not reader.foreign_spans
    position, previous_snapshot, last_type = 76, 0, None
    while position < len(chunk):
        cursor = Cursor(chunk, position)
        event_size, last_type = cursor.varint(), cursor.varint()
        if last_type == 1:
            cursor.varint()
            cursor.varint()
            delta = cursor.s64()
            assert delta == (previous_snapshot - position if previous_snapshot else 0)
            previous_snapshot = position
        position += event_size
    assert position == len(chunk) and last_type == 8
    assert struct.unpack_from(">Q", chunk, 16)[0] == previous_snapshot
    samples = [record for record in reader.records if reader.tname(record[0]) == "virel.ruby.Sample"]
    assert [record[1] for record in samples] == sorted(record[1] for record in samples)
    for _, _, _, values in samples:
        for field, name in [("thread", "virel.ruby.Thread"), ("stack", "virel.ruby.Stack")]:
            tid = next(tid for tid in reader.types if reader.tname(tid) == name)
            assert values[field][1] in reader.pools[tid]
    model = reader.chunk_models[0]
    summary = model["stateSnapshots"][-1]
    expected_summary = [{"typeId": samples[0][0], "emittedCount": len(samples)}] if samples else []
    assert summary["typeSummary"] == expected_summary
    assert model["header"]["state"] == 0 and model["header"]["flags"] == 0x8002
    chunks.append((reader, samples, chunk))
    offset += size

assert len(chunks) == 6
first = chunks[0][1]
assert [sample[1] for sample in first] == [0, 100, 200, 200]
assert [sample[3]["sequence"] for sample in first] == [0, 48, 96, 144]
assert [sample[3]["cpuDelta"] for sample in first] == [0, 50, 40, 10]
assert [sample[3]["wallDelta"] for sample in first] == [0, 100, 100, 0]
assert [sample[3]["truncated"] for sample in first] == [False, False, True, False]
assert len({sample[3]["stack"][1] for sample in first}) == 1
first_reader = chunks[0][0]
pool = lambda name: first_reader.pools[next(tid for tid in first_reader.types if first_reader.tname(tid) == name)]
stack = pool("virel.ruby.Stack")[first[0][3]["stack"][1]]
assert [pool("virel.ruby.Location")[location[1]]["line"] for location in stack["locations"]] == [11, 10]
assert pool("virel.ruby.Function")[1] == {"name": "Example.α", "filename": "example.rb"}
assert chunks[1][1][0][3]["cpuDelta"] == 50
assert chunks[1][1][0][3]["wallDelta"] == 100
assert not chunks[2][1]
assert chunks[3][1][0][3]["cpuTime"] == -1
assert chunks[3][1][0][3]["cpuDelta"] == 0
assert chunks[4][1][0][3]["cpuDelta"] == 50
assert chunks[5][1][0][3]["cpuDelta"] == 0
assert chunks[0][2][68:76] == chunks[4][2][68:76] != chunks[5][2][68:76]
reader = Reader()
reader.record = True
with contextlib.redirect_stdout(io.StringIO()):
    reader.run(data)
assert reader.chunks == 6
print("Virel reference reader: six standalone chunks and concatenation passed")
