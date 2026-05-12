set shell := ["sh", "-c"]
set windows-shell := ["powershell", "-c"]

compile:
    esphome compile mcp23017.yaml

copy:
	@python copy.py

zig:
    zig build

wat:
    wasm2wat chip.wasm

