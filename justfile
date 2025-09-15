set shell := ["sh", "-c"]
set windows-shell := ["powershell", "-c"]

_main:
    @just --list

latest:
    uv tool install copier
    
new ref="main":
    copier copy --vcs-ref {{ref}} gh:mohankumargupta/wokwi-copier-templates . 

