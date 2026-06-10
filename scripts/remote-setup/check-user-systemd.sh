#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no pgg124@136.118.148.167 'bash -s' <<'REMOTE'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
systemctl --user status 2>&1 | head -3
loginctl show-user pgg124 2>/dev/null | grep Linger || true
REMOTE
