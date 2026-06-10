#!/bin/bash
tail -40 /tmp/install.log 2>/dev/null
echo "---"
docker ps 2>/dev/null || sudo docker ps 2>/dev/null || echo "docker not ready"
echo "---"
grep -E 'DONE|FINAL|ERROR|fail' /tmp/install.log 2>/dev/null | tail -5
