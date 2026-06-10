#!/bin/bash
cat > /opt/sentinel/scout/requirements.txt << 'EOF'
playwright
playwright-stealth
python-dotenv
requests
ollama
EOF
echo "Updated scout requirements.txt:"
cat /opt/sentinel/scout/requirements.txt
