# Nexora original-style rebuild — installation

This branch is reserved for the **original-style reconstruction**, not the 3D React dashboard on `main`.

The application archive `nexora-original-complete.zip` must be uploaded to **this branch** before installing. It contains the project files and the `deploy.sh` installer. The original ChatGPT Sites source is not recovered; this is a separately rebuilt React frontend.

Once uploaded, on the Ubuntu/Debian VPS:

```bash
set -e
sudo apt-get update
sudo apt-get install -y git unzip
cd /root
git clone --depth 1 --branch original-style-rebuild-20261110 https://github.com/Rezamoradifar/Nexoramarketglobal.git nexora-original-installer
cd nexora-original-installer
unzip -q nexora-original-complete.zip
cd nexora-original-complete
sudo bash deploy.sh
```

Do not run until `nexora-original-complete.zip` is present in the branch. The installer requires Node 22.12+, Nginx and expects the existing Nexora Nginx port 3080 to proxy to 127.0.0.1:3000. It builds before changing the live symlink and preserves the previous release pointer. It is frontend-only: no active BNB contract, deposits, payouts or live portfolio balances.
