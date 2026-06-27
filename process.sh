#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/.ssh
echo "$SERVER_KEY" | base64 -d > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key
curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
head -1 ~/.ssh/deploy_key
wc -l ~/.ssh/deploy_key
cloudflared access tcp --hostname ssh.obsidianos.xyz --listener 127.0.0.1:2222 &
CF_PID=$!
sleep 2
tar -xzf app.ves manifest.toml
PKG_INFO=$(python3 - <<'PYEOF'
import tomllib, json
with open('manifest.toml', 'rb') as f:
    m = tomllib.load(f)
n = m['name']
deps = m.get('deps', {}).get('vessels', [])
print(n['id'])
print(n['version'])
print(m.get('description', ''))
print(json.dumps(deps))
PYEOF
)

PKG_ID=$(echo "$PKG_INFO"  | sed -n '1p')
PKG_VER=$(echo "$PKG_INFO" | sed -n '2p')
PKG_DESC=$(echo "$PKG_INFO"| sed -n '3p')
PKG_DEPS=$(echo "$PKG_INFO"| sed -n '4p')
DEST="${PKG_ID}-${PKG_VER}.ves"
URL="https://files.obsidianos.xyz/~neo/vessel/${DEST}"
curl -s "https://files.obsidianos.xyz/~neo/vessel/index.toml" > index.toml
python3 - <<PYEOF
import json
deps = json.loads('${PKG_DEPS}')
entry = f'\n[packages.${PKG_ID}]\nversion = "${PKG_VER}"\nurl = "${URL}"\ndescription = "${PKG_DESC}"\n'
if deps:
    entry += 'vessel_deps = [' + ', '.join(f'"{d}"' for d in deps) + ']\n'
with open('index.toml', 'a') as f:
    f.write(entry)
PYEOF
sftp -P 2222 -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no -b - neo@localhost <<SFTPEOF
put app.ves Public/vessel/${DEST}
put index.toml Public/vessel/index.toml
bye
SFTPEOF
kill $CF_PID
gh pr close "$PR_NUMBER" --comment "published as \`${DEST}\` - $URL"
