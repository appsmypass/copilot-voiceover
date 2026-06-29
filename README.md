# Copilot Voice

A hands-free voice assistant for Windows, powered by **your** GitHub Copilot
subscription. Talk to it with your microphone, it talks back, and it can do
anything Copilot's chat models can. Comes with a built-in model picker.

- 🎙️ **Speak or type** — press ENTER to talk, or just type in the box
- 🔊 **Talks back** — Windows text-to-speech reads replies aloud
- 🤖 **Real Copilot models** — GPT-5.x, Claude, Gemini, and more (whatever your plan offers)
- 🔁 **Model picker** — switch models any time
- 🔐 **Your account, your sub** — each user signs in with their own GitHub Copilot account
- 📴 **Offline speech** — voice recognition runs locally (Vosk), no audio leaves your PC

---

## Requirements

- **Windows 10/11** (uses built-in .NET speech for talk-back)
- **An active GitHub Copilot subscription** ([get one here](https://github.com/features/copilot))
- **Python 3** — only needed for microphone input. Skip it and you can still type. ([python.org](https://www.python.org/downloads/))

Everything else (speech engine + offline model) installs itself on first run.

---

## Setup

1. **Download** this folder anywhere (e.g. your Desktop).
2. **Double-click `Copilot Voice.vbs`.** A window opens.
3. **Sign in** the first time:
   - If you're already signed in with the GitHub CLI or the Copilot desktop app, it just works.
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

Run the PowerShell script directly to pass options:

```powershell
powershell -ExecutionPolicy Bypass -File CopilotVoice.ps1 -Model "gpt-5-mini" -Voice "Microsoft David Desktop" -NoVosk
```

| Option    | Description                                            |
|-----------|--------------------------------------------------------|
| `-Model`  | Start on a specific model (otherwise you're prompted)  |
| `-Voice`  | Pick a TTS voice (`Microsoft Zira`/`David Desktop`)    |
| `-NoVosk` | Disable mic, type-only mode                            |
| `-Token`  | Use a specific GitHub token instead of signing in      |

---

## Privacy

- Your sign-in is cached **encrypted** (Windows DPAPI) under
  `%LOCALAPPDATA%\CopilotVoice` — never inside this folder, never in git.
- Speech recognition is **fully offline**. Only your typed/spoken text goes to
  Copilot, same as any Copilot chat.
- `sign out` deletes the cached credential.

---

## Files

| File                | What it is                                  |
|---------------------|---------------------------------------------|
| `Copilot Voice.vbs` | Double-click launcher                       |
| `CopilotVoice.ps1`  | Main app (auth, models, chat, speech)       |
| `listen.py`         | Offline microphone listener (Vosk)          |

## Troubleshooting

- **"Please sign in"** — run again and choose sign in; needs an active Copilot plan.
- **No mic / can't talk** — install Python 3, or use `-NoVosk` and type instead.
- **No talk-back** — pick another `-Voice`; install voices in Windows Settings → Time & language → Speech.
