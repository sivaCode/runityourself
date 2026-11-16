# The commands, in order

Replace ChatGPT Plus with Open WebUI and Ollama on your Mac: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Ollama is ready

```sh
ollama list
```

### Install Python 3.12

```sh
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 brew install python@3.12
python3.12 --version
```

### Install Open WebUI

```sh
python3.12 -m venv ~/open-webui/venv
source ~/open-webui/venv/bin/activate
pip install open-webui==0.13.2
pip list | grep open-webui
```

### Start the server

```sh
(cd ~/open-webui && DATA_DIR=~/open-webui/data ENABLE_OPENAI_API=false nohup open-webui serve --host 127.0.0.1 --port 8080 > serve.log 2>&1 &)
until curl -s http://127.0.0.1:8080/health; do sleep 2; done
netstat -an -p tcp | grep LISTEN | grep 8080
```

### Back up and update

```sh
pkill -f "open-webui serve"
cp -R ~/open-webui/data ~/open-webui/data-backup-$(date +%Y%m%d)
ls ~/open-webui
pip install --upgrade --quiet open-webui==0.13.3
pip list | grep open-webui
(cd ~/open-webui && DATA_DIR=~/open-webui/data ENABLE_OPENAI_API=false nohup open-webui serve --host 127.0.0.1 --port 8080 > serve.log 2>&1 &)
until curl -s http://127.0.0.1:8080/health; do sleep 2; done
```

### Verify

```sh
./verify.sh
```
