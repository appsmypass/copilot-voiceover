"""
Copilot Voice - microphone listener (Vosk, offline, accurate).

Two modes:

1) One-shot (default):
     python listen.py "<model_dir>" [initial_silence_timeout] [max_seconds]
   Opens the mic, transcribes one utterance, prints it to stdout, exits.

2) Persistent server (recommended - loads the model once):
     python listen.py --serve "<model_dir>" "<run_dir>"
   Loads the model and opens the mic ONCE, then waits for commands on stdin:
     - "LISTEN\t<outfile>"  capture one utterance and write the transcript to <outfile>
     - "QUIT"               shut down
   Status is reported via flag files in <run_dir> ("ready" / "error") so the
   parent process never has to parse our stdout/stderr.
"""
import sys
import os
import json
import time
import queue


SAMPLE_RATE = 16000


def capture(rec, q, initial_silence_timeout=8.0, max_seconds=20.0, end_silence=1.2):
    """Capture a single utterance from the audio queue. Returns the transcript text."""
    got_speech = False
    last_partial = ""
    last_change = time.time()
    result_text = ""
    start = time.time()

    # Drain any stale audio buffered before this turn.
    try:
        while True:
            q.get_nowait()
    except queue.Empty:
        pass

    while True:
        now = time.time()
        if not got_speech and (now - start) > initial_silence_timeout:
            break
        if (now - start) > max_seconds:
            break
        if got_speech and (now - last_change) > end_silence:
            break
        try:
            data = q.get(timeout=0.3)
        except queue.Empty:
            continue
        if rec.AcceptWaveform(data):
            res = json.loads(rec.Result())
            txt = res.get("text", "").strip()
            if txt:
                result_text = txt
                break
        else:
            pj = json.loads(rec.PartialResult())
            p = pj.get("partial", "").strip()
            if p and p != last_partial:
                got_speech = True
                last_partial = p
                last_change = time.time()

    if not result_text:
        try:
            res = json.loads(rec.FinalResult())
            result_text = res.get("text", "").strip() or last_partial
        except Exception:
            result_text = last_partial
    return result_text


def one_shot(model_path, initial_silence_timeout, max_seconds):
    try:
        import sounddevice as sd
        from vosk import Model, KaldiRecognizer, SetLogLevel
    except Exception as e:
        sys.stderr.write("DEPS_MISSING: %s\n" % e)
        return 3

    SetLogLevel(-1)
    try:
        model = Model(model_path)
    except Exception as e:
        sys.stderr.write("MODEL_ERROR: %s\n" % e)
        return 4

    rec = KaldiRecognizer(model, SAMPLE_RATE)
    rec.SetWords(False)
    q = queue.Queue()

    def callback(indata, frames, time_info, status):
        q.put(bytes(indata))

    try:
        with sd.RawInputStream(samplerate=SAMPLE_RATE, blocksize=8000, dtype="int16",
                               channels=1, callback=callback):
            sys.stderr.write("LISTENING\n")
            sys.stderr.flush()
            text = capture(rec, q, initial_silence_timeout, max_seconds)
    except Exception as e:
        sys.stderr.write("AUDIO_ERROR: %s\n" % e)
        return 5

    sys.stdout.write(text)
    sys.stdout.flush()
    return 0


def _write_flag(path, content=""):
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception:
        pass


def serve(model_path, run_dir):
    ready_flag = os.path.join(run_dir, "ready")
    err_flag = os.path.join(run_dir, "error")
    try:
        os.makedirs(run_dir, exist_ok=True)
    except Exception:
        pass
    for f in (ready_flag, err_flag):
        try:
            os.remove(f)
        except OSError:
            pass

    try:
        import sounddevice as sd
        from vosk import Model, KaldiRecognizer, SetLogLevel
    except Exception as e:
        _write_flag(err_flag, "DEPS_MISSING: %s" % e)
        return 3

    SetLogLevel(-1)
    try:
        model = Model(model_path)
    except Exception as e:
        _write_flag(err_flag, "MODEL_ERROR: %s" % e)
        return 4

    q = queue.Queue()

    def callback(indata, frames, time_info, status):
        q.put(bytes(indata))

    try:
        stream = sd.RawInputStream(samplerate=SAMPLE_RATE, blocksize=8000, dtype="int16",
                                   channels=1, callback=callback)
        stream.start()
    except Exception as e:
        _write_flag(err_flag, "AUDIO_ERROR: %s" % e)
        return 5

    _write_flag(ready_flag, "ok")

    try:
        while True:
            line = sys.stdin.readline()
            if line == "":  # stdin closed
                break
            line = line.strip()
            if not line:
                continue
            if line == "QUIT":
                break
            if line.startswith("LISTEN"):
                parts = line.split("\t", 1)
                outfile = parts[1] if len(parts) > 1 else None
                rec = KaldiRecognizer(model, SAMPLE_RATE)
                rec.SetWords(False)
                text = capture(rec, q)
                if outfile:
                    tmp = outfile + ".tmp"
                    try:
                        with open(tmp, "w", encoding="utf-8") as f:
                            f.write(text)
                        os.replace(tmp, outfile)
                    except Exception:
                        pass
    finally:
        try:
            stream.stop()
            stream.close()
        except Exception:
            pass
    return 0


def main():
    args = sys.argv[1:]
    if args and args[0] == "--serve":
        if len(args) < 3:
            sys.stderr.write("USAGE: listen.py --serve <model_dir> <run_dir>\n")
            return 2
        return serve(args[1], args[2])

    if not args:
        return 0
    model_path = args[0]
    initial_silence_timeout = float(args[1]) if len(args) > 1 else 8.0
    max_seconds = float(args[2]) if len(args) > 2 else 20.0
    return one_shot(model_path, initial_silence_timeout, max_seconds)


if __name__ == "__main__":
    sys.exit(main())
