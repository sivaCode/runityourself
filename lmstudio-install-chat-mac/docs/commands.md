# The commands, in order

Local AI on your Mac with LM Studio: a 2.10 GB model, Wi-Fi off: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Install llmster

```sh
curl -fsSL https://lmstudio.ai/install.sh | bash 2>&1 | sed "s#$HOME#~#g"
```

### lms on the PATH

```sh
export PATH="$HOME/.lmstudio/bin:$PATH"
grep -c "LM Studio CLI" ~/.zshrc
ls ~/.lmstudio
```

### Start the engine

```sh
lms daemon up
lms daemon status
```

### Download a model

```sh
lms get ibm/granite-4.1-3b -y
lms ls
```

### First chat

```sh
lms chat ibm/granite-4.1-3b --dont-fetch-catalog -p "In two sentences, why does an AI model that runs on my own Mac keep my chats private?"
```

### Wi-Fi off

```sh
networksetup -setairportpower en1 off
networksetup -getairportpower en1
curl -sS -m 5 https://lmstudio.ai -o /dev/null
```

### Ask it offline

```sh
lms chat ibm/granite-4.1-3b --dont-fetch-catalog -p "Write a two-line poem about a Mac that answers with its Wi-Fi off."
```

### Memory and disk

```sh
networksetup -setairportpower en1 on
lms ps
(cd ~/.lmstudio && du -sh bin llmster models)
```

### Verify

```sh
./verify.sh
```
