# Copilot Voice

A hands-free, **agentic** voice assistant for **Windows, macOS, and Linux**, powered
by **your** GitHub Copilot subscription. Talk to it with your microphone, it talks
back, and it can actually **do things on your computer** — open apps, run commands,
read and write files. Comes with a built-in model picker.

- 🎙️ **Speak or type** — press ENTER to talk, or just type in the box
- 🔊 **Talks back** — native text-to-speech reads replies aloud on every OS
- 🦾 **Takes action** — opens apps and websites, runs shell commands, reads/writes files for you
- 🤖 **Real Copilot models** — GPT-5.x, Claude, Gemini, and more (whatever your plan offers)
- 🔁 **Model picker** — switch models any time
- 🔐 **Your account, your sub** — each user signs in with their own GitHub Copilot account
- 📴 **Offline speech** — voice recognition runs locally (Vosk), no audio leaves your computer
- 💻 **One app, every OS** — a single `copilot_voice.py` runs on Windows, macOS, and Linux

---

## What it can do

Just ask, in plain language. Examples:

- "Open my browser and go to github.com"
- "Create a file on my Desktop called notes.txt that says hello"
- "What files are in my Downloads folder?"
- "What's my computer's IP address?"
- "Make a new folder called Projects in my Documents"

Under the hood it uses tools — `open`, `run_shell`, `read_file`, `write_file`,
`list_dir` — so it carries out the request instead of just explaining how. The
`run_shell` tool uses PowerShell on Windows and your default shell (`$SHELL`,
falling back to `/bin/sh`) on macOS and Linux. It runs on **your** computer with
your permissions, so treat it like your own command line.

---

## Requirements

- **Any of Windows 10/11, macOS, or Linux**
- **An active GitHub Copilot subscription** ([get one here](https://github.com/features/copilot))
- **Python 3.8+** — this is the app. ([python.org](https://www.python.org/downloads/))
  - Windows: install from python.org (tick *Add Python to PATH*).
  - macOS: `brew install python` (or python.org).
  - Linux: `sudo apt install python3 python3-pip` (or your distro's package manager).
- **Talk-back (text-to-speech):**
  - Windows — built in (SAPI).
  - macOS — built in (`say`).
  - Linux — install a speech engine: `sudo apt install espeak-ng` (or `espeak` /
    `speech-dispatcher`). Without one, the app still works but won't speak.

Everything else (the offline speech-recognition engine + ~40 MB model) installs
itself on first run. Voice dependencies (`vosk`, `sounddevice`) are auto-installed
with pip the first time you use the microphone; type-only mode needs nothing extra.

---

## Setup & run

1. **Download** this folder anywhere (e.g. your Desktop).
2. **Start it** — pick the launcher for your OS:

   | OS | How to start |
   |----|--------------|
   | **Windows** | Double-click **`run.bat`** (or run `python copilot_voice.py`). The original PowerShell edition still works via **`Copilot Voice.vbs`**. |
   | **macOS** | Double-click **`run.command`** in Finder (or run `./run.sh` in Terminal). |
   | **Linux** | Run **`./run.sh`** in a terminal (or `python3 copilot_voice.py`). |

   On macOS/Linux, make the launcher executable once if needed:
   `chmod +x run.sh run.command`.
3. **Sign in** the first time:
   - If you're already signed in with the GitHub CLI (`gh`) or have a
     `GITHUB_TOKEN`/`GH_TOKEN` set, it just works.
   - Otherwise it opens your browser with a short code — sign in, and Copilot Voice remembers you.
   - No Copilot subscription on that account? It tells you and stops.
4. **Pick a model** by number, and start talking.

That's it. First run downloads a ~40 MB speech model (one time) if you use voice.

---

## How to use

- **Talk:** press **ENTER** on an empty line, then speak.
- **Type:** just write a message and press ENTER.
- **Commands** (say or type):
  - `switch model` — open the model picker
  - `new chat` — clear the conversation
  - `sign out` — forget this account so someone else can sign in
  - `exit` — quit

---

## Options

Pass options on the command line:

```bash
python copilot_voice.py --model gpt-5-mini --no-voice
```

| Option               | Description                                           |
|----------------------|-------------------------------------------------------|
| `-m`, `--model <id>` | Start on a specific model (otherwise you're prompted) |
| `--no-voice`         | Disable the mic, type-only mode                       |
| `--token <token>`    | Use a specific GitHub token instead of signing in     |
| `-y`, `--yes`, `--auto-approve` | Run tool actions without confirming each one (hands-free) |
| `--safe-mode`        | Read-only: disables `run_shell`, `open`, and `write_file` |

The launchers (`run.bat`, `run.sh`, `run.command`) forward any extra arguments
straight through, e.g. `./run.sh --no-voice`.

The original Windows-only PowerShell edition is still available and takes its own
flags: `powershell -ExecutionPolicy Bypass -File CopilotVoice.ps1 -Model gpt-5-mini -NoVosk`.

---

## Privacy

- Your sign-in is cached in a **permission-locked file** in your per-user config
  dir — never inside this folder, never in git. It's restricted to your account
  (`chmod 600` on macOS/Linux; ACL locked to your user via `icacls` on Windows):
  - Windows: `%LOCALAPPDATA%\CopilotVoice`
  - macOS: `~/Library/Application Support/CopilotVoice`
  - Linux: `$XDG_CONFIG_HOME/CopilotVoice` (or `~/.config/CopilotVoice`)
- Speech recognition is **fully offline**. Only your typed/spoken text goes to
  Copilot, same as any Copilot chat.
- `sign out` deletes the cached credential.

---

## Files

| File                | What it is                                              |
|---------------------|---------------------------------------------------------|
| `copilot_voice.py`  | **The app** — cross-platform (Windows/macOS/Linux)      |
| `run.bat`           | Windows launcher (Python app)                           |
| `run.command`       | macOS launcher (double-click in Finder)                 |
| `run.sh`            | Linux/macOS launcher (terminal)                         |
| `Copilot Voice.vbs` | Windows-only launcher for the original PowerShell edition |
| `CopilotVoice.ps1`  | Original Windows PowerShell app (still works)           |
| `listen.py`         | Standalone offline microphone listener (Vosk)           |

## Troubleshooting

- **"Please sign in"** — run again and choose sign in; needs an active Copilot plan.
- **It describes instead of doing** — a few reasoning-heavy models (e.g. some Claude
  variants) prefer to explain. Say `switch model` and pick `gpt-5.4`, `gpt-5-mini`,
  `gpt-5.5`, or a Gemini model for reliable actions.
- **No mic / can't talk** — run with `--no-voice` and type instead. Voice needs
  `vosk` + `sounddevice` (auto-installed on first use); on Linux you may also need
  `sudo apt install portaudio19-dev` before `sounddevice` will build.
- **No talk-back on Linux** — install a TTS engine: `sudo apt install espeak-ng`
  (or `espeak` / `speech-dispatcher`). For nicer voices, `pip install pyttsx3`.
- **No talk-back on Windows/macOS** — talk-back is built in; if silent, check your
  output device and system volume.

## Safety

Copilot Voice can run real actions on your computer with your account's permissions.
To keep that under control:

- **Approval gate (on by default):** before it runs a shell command, opens
  something, or writes a file, it shows you the action and asks you to confirm
  (`y` / `N`, or `a` to allow everything for the rest of the session). Pass
  `-y` / `--yes` to run hands-free if you trust the session.
- **Safe mode:** `--safe-mode` makes it read-only — `run_shell`, `open`, and
  `write_file` are disabled entirely, leaving only `read_file` and `list_dir`.
- **Prompt-injection resistance:** the assistant is told to treat file contents
  and command output as untrusted data, not instructions — so a booby-trapped
  file is less likely to trick it into running something.
- Every tool action is printed in the window, so you can see exactly what happened.

Still, treat it like your own command line: don't approve actions you wouldn't run
yourself, and prefer `--safe-mode` when pointing it at untrusted files or folders.
