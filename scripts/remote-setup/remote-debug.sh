#!/bin/bash
wc -l /tmp/remote_script.sh
head -5 /tmp/remote_script.sh
pgrep -a apt || echo "no apt"
pgrep -a dpkg || echo "no dpkg"
