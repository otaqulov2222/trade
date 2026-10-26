# Opens a reverse tunnel so the Linux VPS can show this Windows dashboard.
# Robot stays on this PC (MetaTrader 5). Do not put passwords in this file.
$ErrorActionPreference = "Stop"
$key = Join-Path $env:USERPROFILE ".ssh\saydirasulov_vps"
ssh -i $key `
  -o StrictHostKeyChecking=accept-new `
  -o ServerAliveInterval=30 `
  -o ServerAliveCountMax=3 `
  -o ExitOnForwardFailure=yes `
  -N -R 127.0.0.1:8765:127.0.0.1:8765 `
  root@77.83.206.192
