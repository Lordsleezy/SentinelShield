#!/usr/bin/env bash
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no root@136.118.148.167 'whoami' 2>&1 || echo root-failed
sshpass -p maddy123 ssh -o StrictHostKeyChecking=no pgg124@136.118.148.167 'getent passwd | head -5; ls -la /home'
