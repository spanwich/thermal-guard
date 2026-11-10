# thermal-guard
thermal-guard for Dell Pro Max AI GB10

## What does this script do:
Problem: my Dell Pro max GB10 Always thermal shutdown during heavy load.

Solution: I ask Claude to create the script to cap the frequency to 1.8GHz when reaching 90 degrees to avoid thermal shuwdown.

### Move the script to /usr/local/bin
```bash
sudo mv thermal-guard.sh /usr/local/bin/thermal-guard.sh
sudo chmod +x /usr/local/bin/thermal-guard.sh
```

### Tun as service that starts on boot:
```bash
sudo tee /etc/systemd/system/thermal-guard.service <<'EOF'
[Unit]
Description=Pause LLM container when the GB10 overheats
After=docker.service
Wants=docker.service

[Service]
ExecStart=/usr/local/bin/thermal-guard.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now thermal-guard
```

Co-authored-by: Claude <noreply@anthropic.com>
