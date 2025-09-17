import sys
import shutil
from pathlib import Path

def main():
    build_base = Path(".esphome") / "build" / "veryverbose" / ".pioenvs"/ "veryverbose"
    firmware_bin = "firmware.factory.bin"
    firmware_elf = "firmware.elf"
    firmware_bin_full_path = build_base / firmware_bin 
    firmware_elf_full_path = build_base / firmware_elf

    dest_dir = Path("./firmware")
    dest_dir.mkdir(exist_ok=True)
    print(firmware_bin_full_path)
    shutil.copy2(firmware_bin_full_path, dest_dir / firmware_bin)
    shutil.copy2(firmware_elf_full_path,  dest_dir / firmware_elf)

if __name__ == "__main__":
    main()

