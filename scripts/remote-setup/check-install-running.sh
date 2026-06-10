#!/bin/bash
ps aux | grep remote_script | grep -v grep
ps aux | grep install-services | grep -v grep
ps aux | grep apt | grep -v grep | head -5
ls -la /tmp/remote_script.sh 2>/dev/null
