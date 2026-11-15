# Run It Yourself: the commands

The scripts and commands from the **Run It Yourself** videos: self-hosting and local AI on a Mac, installed for real
on camera and checked with a verify script. One folder per video:

| Folder | Video |
|---|---|
| [colima-docker-mac-basics](colima-docker-mac-basics/) | Replace Docker Desktop with Colima on your Mac: $0 vs $24/mo |
| [local-ai-memory-measured-mac](local-ai-memory-measured-mac/) | Local AI on your 16 GB Mac with Ollama: 5.3 GB for an 8B model |
| [private-ai-chat-ollama-mac](private-ai-chat-ollama-mac/) | Run a private AI chatbot on your Mac with Ollama: real speed numbers |

Each folder has:
- `README.md`: what it sets up, what you need, the steps, licences, backups and updates;
- `install.sh`, `verify.sh`, `uninstall.sh` (and any helper or config): the same steps as the video, with checks.
  `verify.sh` ends with `ALL CHECKS PASSED`; `uninstall.sh` puts your Mac back the way `install.sh` found it;
- `docs/commands.md`: every command the video runs, in order;
- `docs/architecture.html`: what it builds, as a diagram (open it in a browser);
- `docs/references.md`: the sources behind every number and claim, with the date each was read.

Read a script before you run it. They were tested on the Mac and versions their README names; yours may differ.
The scripts are MIT licensed (LICENSE). The software they install keeps its own licence (each README lists it).
