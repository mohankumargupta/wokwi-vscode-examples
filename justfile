set shell := ["sh", "-c"]
set windows-shell := ["powershell", "-c"]

latest:
    uv tool install esphome 
    uv tool install pip

