set shell := ["sh", "-c"]
set windows-shell := ["powershell", "-c"]

_main:
    @just --list

prereq:
  uv tool install esphome --force --with pip,wheel,fatfs-ng,littlefs-python

prereq_version version:
  uv tool install esphome=={{ version }} --force  --with pip,wheel,fatfs-ng,littlefs-python

latest:
    uv tool install copier
    
new ref="main":
    copier copy --vcs-ref {{ref}} gh:mohankumargupta/wokwi-copier-templates . 

