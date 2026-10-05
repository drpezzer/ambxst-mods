#!/usr/bin/env python3
"""Ambxst Roadie (drpezzer.roadie): the AI sidebar's bridge to Claude Code.

    roadie_claude_code.py run <body.json> <request id>
    roadie_claude_code.py probe

`run` is what the sidebar starts in place of curl when a Claude Code model is
picked (ClaudeCodeStrategy.qml writes the body and the command line). It runs
ONE turn of the `claude` CLI, logged in the way the CLI already is, so no API
key is involved, and prints one JSON object per line on stdout:

    {"t": "<markdown to append to the reply>"}
    {"s": "<what Claude is doing right now>"}

"t" is what Claude says to the user, and the only thing kept in the chat. "s"
is the line under the chat while the turn runs (Thinking, Running ..., Reading
...): each one replaces the one before and none is kept, the way the terminal
shows a tool call while it works. Problems are printed as "t". Always exits 0
for that reason.

Follow-up messages resume the same Claude Code session. The sidebar sends the
whole chat every time and knows nothing about sessions, so the session is
found by content: after each reply a digest of the chat as it then stands is
stored beside the session id, and a request whose earlier messages have that
digest continues that session. A chat that was edited, regenerated, started
with another provider or whose session is gone matches nothing, and starts a
new session with the earlier messages handed over as a transcript.

What the sidebar shows about a chat comes from the same state file
(~/.local/state/ambxst/roadie-claude-code.json, watched by RoadieClaudeCode):

    sessions  per Claude Code session: the chat it belongs to, its label, the
              model that answered, how much of the context window is in use
    limit     how much of the 5-hour limit is used, as of the last turn
    models    what the CLI's model aliases currently stand for

A chat is labelled the way `claude --resume` labels its session: the name the
session was given, else Claude Code's own title for it. Sessions run this way
get neither by themselves, so a short title is written after the first reply
(a small detached `title` job on the quickest model) and handed to the session
as its name on the next turn; until then the sidebar shows that title and the
terminal shows the first message.

    roadie_claude_code.py probe      {"found", "path", "version"} for Settings > AI
    roadie_claude_code.py refresh    read the sessions' labels again (a session
                                     may have been renamed or continued in a terminal)
    roadie_claude_code.py models     learn what the model aliases stand for
    roadie_claude_code.py title      (internal) write a title; reads JSON on stdin
    roadie_claude_code.py gate       (internal) Claude Code's hook before a Bash call

A command that needs root cannot be run by Claude Code here: sudo has no
terminal to ask for the password on. `gate` is hooked in before every Bash
call of a turn. A call that uses sudo is not run; it is written down, Claude is
told that the user is being asked, and when the turn ends `run` prints

    {"sudo": {"command": "...", "cwd": "..."}}

which the sidebar turns into a box of its own under the reply: "Run this sudo
command?". Yes runs it there (RoadieSudo.qml) and sends its output back as the
next message; No leaves it, and the next message says it was not run.

Python standard library only.
"""

import contextlib
import fcntl
import glob
import hashlib
import json
import re
import shlex
import tempfile
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid

MARK = "claude-code"
STATE_KEEP = 200            # sessions remembered
TRANSCRIPT_LIMIT = 60000    # characters of earlier chat handed to a new session
BODY_WAIT = 4.0             # seconds to wait for the sidebar to finish writing the body
MODELS_MAX_AGE = 7 * 86400  # the aliases are asked again after this long, or a CLI update
ALIASES = ("", "fable", "opus", "sonnet", "haiku")   # "" = the model Claude Code is set to
RETITLE_AT = 3              # user messages after which the title is written once more

# What each access level turns into on the command line. Nobody can answer a
# permission prompt from the sidebar, so every level is one where Claude Code
# decides by itself; what it may not do is refused, never left hanging.
WEB = ["WebSearch", "WebFetch"]
ACCESS = {
    "chat": ["--tools", "", "--permission-mode", "dontAsk"],
    "read": ["--permission-mode", "dontAsk", "--allowedTools", *WEB],
    "edit": ["--permission-mode", "acceptEdits", "--allowedTools", *WEB],
    "auto": ["--permission-mode", "auto"],
}
ACCESS_NAMES = {"chat": "Chat only", "read": "Read only", "edit": "Edit files", "auto": "Auto"}

# Set by a Claude Code session for the programs it starts. A shell that was
# itself started from one must not hand them on: the turn would attach to that
# session instead of being its own.
INHERITED = (
    "CLAUDECODE", "CLAUDE_PID", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH",
    "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
)

TITLE_PROMPT = (
    "You name conversations. Reply with only a title of three to seven words that says what "
    "the conversation below is about, in sentence case, with no quotes and no full stop."
)

SIDEBAR_PROMPT = (
    "You are being used through the AI sidebar of the Ambxst desktop shell, not a terminal. "
    "Replies are rendered as Markdown in a narrow chat bubble: keep them short, and avoid wide "
    "tables and long unbroken lines. Nobody can answer a permission prompt here. The access "
    "level of this chat is \"{access}\"; if a tool is refused, say what you wanted to do and "
    "that the level can be changed under Settings > AI > Claude Code."
)

SUDO_PROMPT = (
    " When a command needs root, call Bash with sudo as you normally would, one command at a "
    "time. It is not run by you: the sidebar shows it to the user, who can run it with one "
    "click, and its output then arrives as your next message. It runs without a terminal, so "
    "nothing can answer its questions: add flags such as --noconfirm when the user has agreed "
    "to what it will do."
)

GATE_REPLY = (
    "Not run. Commands that need root are run by the user from the sidebar, and they are being "
    "asked about this one now. End your reply here, with one line on what the command is for. "
    "If they agree, its output arrives as your next message; if not, they will say what to do "
    "instead. Do not look for another way to get root."
)

GATE_BUSY = "Not run. The user is already being asked about another root command: one at a time. End your reply here."


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "ambxst", "roadie-claude-code.json")


def load_state():
    try:
        with open(state_path(), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    if not isinstance(data.get("sessions"), dict):
        # 2.2.0's first layout was the sessions and nothing else.
        old = {k: v for k, v in data.items() if isinstance(v, dict) and "digest" in v}
        data = {"sessions": old}
    data.setdefault("models", {})
    return data


def save_state(state):
    path = state_path()
    try:
        sessions = state.get("sessions", {})
        if len(sessions) > STATE_KEEP:
            newest = sorted(sessions.items(), key=lambda kv: kv[1].get("at", 0), reverse=True)
            state["sessions"] = dict(newest[:STATE_KEEP])
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


@contextlib.contextmanager
def locked_state():
    """Read, change, write: a turn, a title job and the alias check can all
    finish at once."""
    path = state_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_state()
        yield state
        save_state(state)


def find_claude():
    found = shutil.which("claude")
    if found:
        return found
    home = os.path.expanduser("~")
    for path in (
        home + "/.local/bin/claude",
        home + "/.claude/local/claude",
        home + "/.npm-global/bin/claude",
        home + "/.bun/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
    ):
        if os.access(path, os.X_OK):
            return path
    return ""


def clean_env():
    env = dict(os.environ)
    for key in INHERITED:
        env.pop(key, None)
    return env


def probe():
    path = find_claude()
    version = cli_version(path) if path else ""
    print(json.dumps({"found": bool(path), "path": path, "version": version}), flush=True)


def cli_version(path):
    try:
        out = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=15, env=clean_env())
        return (out.stdout or "").strip().split(" ")[0]
    except (OSError, subprocess.SubprocessError):
        return ""


# ── what `claude --resume` calls a session ───────────────────────────────────

def session_file(session):
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    found = glob.glob(os.path.join(glob.escape(base), "projects", "*", glob.escape(session) + ".jsonl"))
    return found[0] if found else ""


def session_label(entry, session):
    """The name the session was given, else Claude Code's own title for it.
    Kept with the file's size and time, so an unchanged file is not read again."""
    path = session_file(session)
    if not path:
        return entry.get("label", "")
    try:
        st = os.stat(path)
    except OSError:
        return entry.get("label", "")
    stamp = [int(st.st_mtime), st.st_size]
    if entry.get("stamp") == stamp:
        return entry.get("label", "")
    named, titled = "", ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"custom-title"' not in line and '"ai-title"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("type") == "custom-title" and rec.get("customTitle"):
                    named = str(rec["customTitle"])
                elif rec.get("type") == "ai-title" and rec.get("aiTitle"):
                    titled = str(rec["aiTitle"])
    except OSError:
        return entry.get("label", "")
    entry["stamp"] = stamp
    entry["label"] = named or titled
    return entry["label"]


def refresh():
    with locked_state() as state:
        for session, entry in state["sessions"].items():
            if isinstance(entry, dict) and entry.get("chat"):
                session_label(entry, session)


def title_job():
    """Detached from the turn that started it: the reply is already on screen."""
    try:
        job = json.loads(sys.stdin.read())
    except ValueError:
        return
    claude = find_claude()
    if not claude or not job.get("session") or not job.get("text"):
        return
    try:
        out = subprocess.run(
            [claude, "-p", "--model", "haiku", "--tools", "", "--strict-mcp-config",
             "--no-session-persistence", "--permission-mode", "dontAsk", "--system-prompt", TITLE_PROMPT],
            input="<conversation>\n%s\n</conversation>" % job["text"],
            capture_output=True, text=True, timeout=90, env=clean_env(), cwd=os.path.expanduser("~"),
        )
    except (OSError, subprocess.SubprocessError):
        return
    lines = [l.strip() for l in (out.stdout or "").splitlines() if l.strip()]
    if out.returncode != 0 or not lines:
        return
    title = lines[0].strip("\"'`*# ").rstrip(".")
    if not title or len(title) > 90:
        return
    with locked_state() as state:
        entry = state["sessions"].get(job["session"])
        if isinstance(entry, dict):
            entry["title"] = title
            entry["titleUsers"] = int(job.get("users") or 1)


def start_title_job(session, chat):
    parts = []
    for m in chat[-12:]:
        who = "User" if m["role"] == "user" else "Assistant"
        parts.append("%s: %s" % (who, short(m["content"], 700)))
    job = {"session": session, "users": sum(1 for m in chat if m["role"] == "user"), "text": "\n\n".join(parts)}
    try:
        child = subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "title"],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True, text=True,
        )
        child.stdin.write(json.dumps(job))
        child.stdin.close()
    except OSError:
        pass


# ── what the aliases stand for ───────────────────────────────────────────────

def alias_model(claude, alias, found):
    """The CLI names the model it resolved an alias to as the turn starts. Ask,
    read that, and end it there: nothing needs to be answered."""
    argv = [claude, "-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
            "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--permission-mode", "dontAsk",
            "--system-prompt", "."]
    if alias:
        argv += ["--model", alias]
    try:
        child = subprocess.Popen(argv, cwd=os.path.expanduser("~"), env=clean_env(), text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
    except OSError:
        return
    timer = threading.Timer(40, lambda: child.poll() is None and os.killpg(child.pid, signal.SIGKILL))
    timer.daemon = True
    timer.start()
    try:
        child.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": "hi"}}) + "\n")
        child.stdin.flush()
        for line in child.stdout:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "system" and ev.get("subtype") == "init":
                if ev.get("model"):
                    found[alias] = str(ev["model"])
                break
    except (OSError, ValueError):
        pass
    finally:
        timer.cancel()
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass
        child.wait()


def models(force):
    claude = find_claude()
    if not claude:
        return
    version = cli_version(claude)
    state = load_state()
    fresh = (state.get("modelsVersion") == version
             and time.time() - state.get("modelsAt", 0) < MODELS_MAX_AGE
             and all(a in state.get("models", {}) for a in ALIASES))
    if fresh and not force:
        return
    found = {}
    threads = [threading.Thread(target=alias_model, args=(claude, a, found)) for a in ALIASES]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if not found:
        return
    with locked_state() as state:
        state["models"].update(found)
        state["modelsVersion"] = version
        state["modelsAt"] = int(time.time())


# ── commands that need root ──────────────────────────────────────────────────

LEADERS = {"then", "do", "else", "elif", "exec", "time", "nohup", "!", "{", "env", "command"}


def wants_root(command):
    """Is sudo one of the commands this line runs (and not a word in a string)?"""
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return bool(re.search(r"(^|[;&|(\s])sudo(\s|$)", command))
    before = None
    for token in tokens:
        if token == "sudo":
            starts = before is None or before in LEADERS or not before.strip("();<>|&") or re.match(r"^\w+=", before)
            if starts:
                return True
        before = token
    return False


def gate():
    """PreToolUse hook for Bash. Exit status 2 means "do not run", and what is
    on stderr is what Claude is told."""
    try:
        call = json.loads(sys.stdin.read())
    except ValueError:
        return 0
    command = str((call.get("tool_input") or {}).get("command") or "")
    path = os.environ.get("ROADIE_SUDO_REQUEST", "")
    if not path or not wants_root(command):
        return 0
    try:
        # "x": the first one asked in a turn is the one the user is shown.
        with open(path, "x", encoding="utf-8") as f:
            json.dump({"command": command, "cwd": str(call.get("cwd") or "")}, f)
    except FileExistsError:
        sys.stderr.write(GATE_BUSY)
        return 2
    except OSError:
        return 0
    sys.stderr.write(GATE_REPLY)
    return 2


# ── the chat as the sidebar sends it ─────────────────────────────────────────

def turns(messages):
    """The user and assistant messages, in order. The sidebar's own notices
    (role system) are not part of the conversation."""
    out = []
    for m in messages or []:
        if not isinstance(m, dict):
            continue
        role = m.get("role")
        if role == "function":
            role = "user"
        if role not in ("user", "assistant"):
            continue
        out.append({
            "role": role,
            "content": m.get("content") or "",
            "attachments": m.get("attachments") or [],
        })
    return out


def digest(chat):
    plain = [[m["role"], m["content"], len(m["attachments"])] for m in chat]
    return hashlib.sha256(json.dumps(plain, ensure_ascii=False).encode("utf-8")).hexdigest()


def transcript(chat):
    lines = []
    for m in chat:
        who = "User" if m["role"] == "user" else "Assistant"
        text = m["content"].strip()
        if m["attachments"]:
            text = (text + "\n" if text else "") + "[%d image(s) attached]" % len(m["attachments"])
        lines.append("%s: %s" % (who, text))
    text = "\n\n".join(lines)
    if len(text) > TRANSCRIPT_LIMIT:
        text = "[earlier messages left out]\n\n" + text[-TRANSCRIPT_LIMIT:]
    return text


def user_content(message, earlier):
    blocks = []
    for att in message["attachments"]:
        if isinstance(att, dict) and att.get("type") == "image" and att.get("base64"):
            blocks.append({
                "type": "image",
                "source": {"type": "base64", "media_type": att.get("mimeType") or "image/png", "data": att["base64"]},
            })
    text = message["content"]
    if earlier:
        text = (
            "This chat already has earlier messages. They were not part of this session, "
            "so here they are as a transcript:\n\n<transcript>\n" + transcript(earlier)
            + "\n</transcript>\n\nCarry on from there. The new message:\n\n" + text
        )
    blocks.append({"type": "text", "text": text or "(no text)"})
    return blocks


# ── what a tool call looks like in the status line ──────────────────────────

def short(text, limit=90, keep_end=False):
    text = " ".join(str(text).split()).replace("`", "'")
    if len(text) <= limit:
        return text
    return "…" + text[-(limit - 1):] if keep_end else text[: limit - 1] + "…"


def home_short(path, cwd=""):
    home = os.path.expanduser("~")
    path = str(path)
    if cwd and path.startswith(cwd.rstrip("/") + "/"):
        return path[len(cwd.rstrip("/")) + 1:]
    return "~" + path[len(home):] if path == home or path.startswith(home + "/") else path


def tool_status(name, args, cwd=""):
    """What the sidebar says Claude is doing while this tool runs."""
    args = args if isinstance(args, dict) else {}
    path = short(home_short(args.get("file_path") or args.get("notebook_path") or "", cwd), 60, True)
    if name == "Bash":
        said = short(args.get("description", ""), 110)
        return said or "Running %s" % short(args.get("command", ""), 100)
    if name == "Read":
        return "Reading %s" % path
    if name in ("Edit", "MultiEdit", "NotebookEdit"):
        return "Editing %s" % path
    if name == "Write":
        return "Writing %s" % path
    if name == "Grep":
        return "Searching for %s" % short(args.get("pattern", ""), 80)
    if name == "Glob":
        return "Looking for files %s" % short(args.get("pattern", ""), 80)
    if name == "WebSearch":
        return "Searching the web for %s" % short(args.get("query", ""), 80)
    if name == "WebFetch":
        return "Reading %s" % short(args.get("url", ""), 90)
    if name in ("Task", "Agent"):
        said = short(args.get("description", ""), 90)
        return "Agent: %s" % said if said else "Working with an agent"
    if name == "Skill":
        return "Using the %s skill" % short(args.get("skill", ""), 60)
    if name == "TodoWrite":
        return "Updating its to-do list"
    if name.startswith("mcp__"):
        return "Using %s" % short(name[5:].replace("__", ": "), 80)
    return "Using %s" % short(name, 60)


# ── one turn ─────────────────────────────────────────────────────────────────

class Turn:
    def __init__(self):
        self.text = ""          # everything sent to the sidebar so far
        self.doing = ""         # the status line last sent
        self.child = None
        self.current = ""       # id of the message being streamed
        self.model = ""         # the model that answered, as the CLI names it
        self.used = 0           # tokens in the context window after the last reply
        self.window = 0         # its size
        self.limit = None       # {"fiveHour": 0..1, "resetsAt": epoch}
        self.env = {}           # added to the CLI's environment
        self.stopping = False
        self.lock = threading.Lock()

    def emit(self, text):
        if not text:
            return
        with self.lock:
            self.text += text
            try:
                sys.stdout.write(json.dumps({"t": text}) + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, OSError, ValueError):
                # The sidebar is gone (shell reload): nobody is reading.
                self.stopping = True
                self.kill()

    def block(self, text):
        """A paragraph of its own."""
        with self.lock:
            lead = "" if not self.text or self.text.endswith("\n\n") else ("\n" if self.text.endswith("\n") else "\n\n")
        self.emit(lead + text)

    def status(self, text):
        """What Claude is doing right now. Shown under the chat while the turn
        runs and never kept: only what Claude says goes into the bubble."""
        with self.lock:
            if text == self.doing:
                return
            self.doing = text
            try:
                sys.stdout.write(json.dumps({"s": text}) + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, OSError, ValueError):
                self.stopping = True
                self.kill()

    def gap(self):
        """Text is about to start: keep it off the paragraph before it."""
        with self.lock:
            need = bool(self.text) and not self.text.endswith("\n\n")
            lead = "\n" if self.text.endswith("\n") else "\n\n"
        if need:
            self.emit(lead)

    def kill(self):
        child = self.child
        if child is None or child.poll() is not None:
            return
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                child.terminate()
            except OSError:
                pass

        def insist():
            # Asked nicely and still there: it does not get to outlive the chat.
            try:
                child.wait(timeout=4)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError, OSError):
                    pass

        threading.Thread(target=insist, daemon=True).start()

    def note_limit(self, info):
        if not isinstance(info, dict):
            return
        five = (info.get("unifiedWindows") or {}).get("five_hour")
        if not isinstance(five, dict) and info.get("rateLimitType") == "five_hour":
            five = info
        if isinstance(five, dict) and isinstance(five.get("utilization"), (int, float)):
            self.limit = {"fiveHour": float(five["utilization"]), "resetsAt": int(five.get("resetsAt") or 0),
                          "at": int(time.time())}

    def run(self, argv, cwd, content):
        """Runs the CLI once. Returns (session id, saw the turn start, error text)."""
        try:
            self.child = subprocess.Popen(
                argv, cwd=cwd, env=dict(clean_env(), **self.env), text=True, encoding="utf-8", errors="replace",
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                start_new_session=True,
            )
        except OSError as e:
            return "", False, "could not start `%s`: %s" % (argv[0], e)
        child = self.child

        stderr = []
        threading.Thread(target=lambda: stderr.append(child.stderr.read()), daemon=True).start()
        try:
            child.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n")
            child.stdin.close()
        except (BrokenPipeError, OSError):
            pass

        session = ""
        started = False
        streamed = set()    # message ids whose text arrived as deltas
        tools = set()
        error = ""
        failed = ""         # set when the turn failed without saying why on stdout
        for line in child.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if not isinstance(ev, dict):
                continue
            kind = ev.get("type")
            if ev.get("session_id") and not session:
                session = ev["session_id"]
            if kind == "system" and ev.get("subtype") == "init" and ev.get("model"):
                self.model = str(ev["model"])
            elif kind == "rate_limit_event":
                self.note_limit(ev.get("rate_limit_info"))
            if ev.get("parent_tool_use_id"):
                continue    # a subagent talking to itself
            if kind == "stream_event":
                started = True
                inner = ev.get("event") or {}
                if inner.get("type") == "message_start":
                    self.current = (inner.get("message") or {}).get("id", "")
                    self.status("Thinking")
                elif inner.get("type") == "content_block_start":
                    began = (inner.get("content_block") or {}).get("type")
                    if began == "text":
                        self.gap()
                        self.status("Writing")
                    elif began == "thinking":
                        self.status("Thinking")
                elif inner.get("type") == "content_block_delta":
                    delta = inner.get("delta") or {}
                    if delta.get("type") == "text_delta" and delta.get("text"):
                        streamed.add(self.current)
                        self.emit(delta["text"])
            elif kind == "assistant":
                started = True
                msg = ev.get("message") or {}
                usage = msg.get("usage")
                if isinstance(usage, dict):
                    # What that request held is what the next one starts from.
                    self.used = sum(int(usage.get(k) or 0) for k in (
                        "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"))
                for part in msg.get("content") or []:
                    if not isinstance(part, dict):
                        continue
                    if part.get("type") == "tool_use" and part.get("id") not in tools:
                        tools.add(part.get("id"))
                        if (part.get("name") == "Bash" and self.env.get("ROADIE_SUDO_REQUEST")
                                and wants_root(str((part.get("input") or {}).get("command") or ""))):
                            continue    # not run: the sidebar shows it in a box of its own
                        self.status(tool_status(part.get("name", "tool"), part.get("input"), cwd))
                    elif part.get("type") == "text" and msg.get("id") not in streamed and part.get("text"):
                        # A CLI that does not send partial messages.
                        self.gap()
                        self.emit(part["text"])
            elif kind == "user":
                self.status("Thinking")     # a tool's result went back to Claude
            elif kind == "result":
                started = True
                per_model = ev.get("modelUsage")
                if isinstance(per_model, dict):
                    mine = per_model.get(self.model)
                    if not isinstance(mine, dict):
                        mine = max((v for v in per_model.values() if isinstance(v, dict)),
                                   key=lambda v: v.get("contextWindow") or 0, default={})
                    self.window = int(mine.get("contextWindow") or 0) or self.window
                if ev.get("is_error"):
                    said = ev.get("errors")
                    said = "; ".join(str(x) for x in said) if isinstance(said, list) else ""
                    error = str(ev.get("result") or said or "")
                    failed = str(ev.get("subtype") or "the turn failed")
                elif not self.text and ev.get("result"):
                    self.emit(str(ev["result"]))
        code = child.wait()
        if not error and (failed or code != 0) and not self.stopping:
            tail = "".join(stderr).strip().splitlines()
            error = tail[-1] if tail else (failed or "claude exited with status %d" % code)
        return session, started, error


def read_body(path, request):
    """The sidebar writes the body and starts this at the same moment, so the
    file may still hold the request before this one."""
    deadline = time.monotonic() + BODY_WAIT
    while True:
        try:
            with open(path, encoding="utf-8") as f:
                body = json.load(f)
            if isinstance(body, dict) and body.get("roadie") == MARK and (not request or body.get("request") == request):
                return body
        except (OSError, ValueError):
            pass
        if time.monotonic() > deadline:
            return None
        time.sleep(0.05)


def run(path, request):
    turn = Turn()

    def stop(*_):
        turn.stopping = True
        turn.kill()

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, stop)

    # A shell that is killed outright leaves this running with nobody to tell
    # it; ending up with a different parent is the sign.
    parent = os.getppid()

    def watch():
        while not turn.stopping:
            time.sleep(1.0)
            if os.getppid() != parent:
                stop()
                return

    threading.Thread(target=watch, daemon=True).start()

    body = read_body(path, request)
    if body is None:
        turn.emit("**Claude Code:** the request never arrived (%s)." % path)
        return
    chat = turns(body.get("messages"))
    if not chat or chat[-1]["role"] != "user":
        turn.emit("**Claude Code:** there is no message to answer.")
        return

    claude = find_claude()
    if not claude:
        turn.emit(
            "**Claude Code was not found.** Install it (see https://claude.com/claude-code), "
            "run `claude` once in a terminal to log in, then send the message again."
        )
        return

    access = body.get("access") if body.get("access") in ACCESS else "read"
    cwd = os.path.expanduser(str(body.get("cwd") or "").strip() or "~")
    if not os.path.isdir(cwd):
        turn.emit("**Claude Code:** the working folder `%s` does not exist. Change it under Settings > AI." % home_short(cwd))
        cwd = os.path.expanduser("~")
    cwd = os.path.realpath(cwd)

    system = SIDEBAR_PROMPT.format(access=ACCESS_NAMES[access])
    extra = str(body.get("system") or "").strip()
    if extra:
        system += "\n\n" + extra

    base = [claude, "-p", "--output-format", "stream-json", "--input-format", "stream-json",
            "--verbose", "--include-partial-messages", "--append-system-prompt", system]
    base += ACCESS[access]

    # Where `gate` writes down a command that needs root (see the top).
    asked = ""
    if access != "chat":
        runtime = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        asked = os.path.join(runtime, "roadie-sudo-%d-%s.json" % (os.getpid(), uuid.uuid4().hex[:8]))
        turn.env["ROADIE_SUDO_REQUEST"] = asked
        hook = "%s %s gate" % (shlex.quote(sys.executable or "python3"), shlex.quote(os.path.abspath(__file__)))
        base += ["--settings", json.dumps({"hooks": {"PreToolUse": [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": hook}]}]}})]
        system += SUDO_PROMPT
        base[base.index("--append-system-prompt") + 1] = system
    model = str(body.get("model") or "").strip()
    if model:
        base += ["--model", model]

    earlier, message = chat[:-1], chat[-1]
    chat_id = str(body.get("chat") or "")
    sessions = load_state()["sessions"]
    known = None
    if earlier:
        want = digest(earlier)
        for sid, entry in sessions.items():
            if isinstance(entry, dict) and entry.get("digest") == want and entry.get("cwd") == cwd:
                known = sid
                break

    session, started, error = "", False, ""
    naming = ""
    if known:
        # A title written since the last turn becomes the session's name, once:
        # a name given in a terminal afterwards is not written over.
        before = sessions[known]
        if before.get("title") and before.get("named") != before["title"]:
            naming = before["title"]
        resume = base + ["--resume", known] + (["--name", naming] if naming else [])
        session, started, error = turn.run(resume, cwd, user_content(message, []))
        if (error or not started) and not turn.text and not turn.stopping:
            # The session is gone, or cannot be continued: start over with a
            # transcript. Whatever is wrong beyond that shows up there too.
            with locked_state() as state:
                state["sessions"].pop(known, None)
            known, naming = None, ""
    if not known:
        fresh = str(uuid.uuid4())
        session, started, error = turn.run(base + ["--session-id", fresh], cwd, user_content(message, earlier))
        session = session or fresh

    if error and not turn.stopping:
        hint = ""
        low = error.lower()
        if "login" in low or "api key" in low or "authenticat" in low:
            hint = " Run `claude` in a terminal once to log in."
        elif "option" in low or "argument" in low:
            hint = " This needs a recent Claude Code: run `claude update`."
        turn.block("**Claude Code:** %s%s" % (error, hint))

    if asked:
        try:
            with open(asked, encoding="utf-8") as f:
                wanted = json.load(f)
            os.unlink(asked)
            if wanted.get("command") and not turn.stopping:
                wanted["cwd"] = wanted.get("cwd") or cwd
                # Not part of the reply: the sidebar makes a box of it.
                sys.stdout.write(json.dumps({"sudo": wanted}) + "\n")
                sys.stdout.flush()
        except (OSError, ValueError):
            pass

    with locked_state() as state:
        if turn.limit:
            state["limit"] = turn.limit
        if turn.model:
            state["models"][model] = turn.model
        if not (started and session and turn.text):
            return
        entry = state["sessions"].pop(known, None) if known else None
        entry = entry if isinstance(entry, dict) else {}
        full = chat + [{"role": "assistant", "content": turn.text, "attachments": []}]
        users = sum(1 for m in full if m["role"] == "user")
        entry.update(digest=digest(full), cwd=cwd, at=int(time.time()), chat=chat_id, users=users)
        if turn.model:
            entry["model"] = turn.model
        if turn.used and turn.window:
            entry["context"] = {"used": turn.used, "window": turn.window}
        if naming:
            entry["named"] = naming
        session_label(entry, session)
        state["sessions"][session] = entry
        written = entry.get("titleUsers", 0)
        # Only while the label is still ours to write: not once the session
        # has been named in a terminal, or Claude Code has titled it itself.
        ours = not entry.get("label") or entry.get("label") == entry.get("named")
        retitle = ours and (not written or users >= RETITLE_AT > written)
    if retitle and not turn.stopping:
        start_title_job(session, full)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "probe":
        probe()
    elif len(sys.argv) >= 2 and sys.argv[1] == "refresh":
        refresh()
    elif len(sys.argv) >= 2 and sys.argv[1] == "models":
        models("--force" in sys.argv)
    elif len(sys.argv) >= 2 and sys.argv[1] == "title":
        title_job()
    elif len(sys.argv) >= 2 and sys.argv[1] == "gate":
        return gate()
    elif len(sys.argv) >= 3 and sys.argv[1] == "run":
        try:
            run(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
        except Exception as e:  # the sidebar shows text and nothing else
            try:
                print(json.dumps({"t": "\n\n**Claude Code:** the bridge failed: %s" % e}), flush=True)
            except Exception:
                pass
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
