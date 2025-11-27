# phpBB Argon2 Hasher (Python CLI)

A tiny, pure-Python command-line tool to generate and verify phpBB3-compatible Argon2 password hashes (PHC format like `$argon2id$…`). Works with Python 3.13 on macOS and uses uv for a clean, reproducible setup.

## Features
- Outputs standard PHC strings compatible with phpBB3 (`$argon2id$…` or `$argon2i$…`).
- Adjustable Argon2 parameters (time, memory, parallelism, hash length, salt length).
- Secure password input via prompt (or `--stdin` / `--password` when necessary).
- Verify an existing hash with `--verify`.

## Quick Start (macOS, Python 3.13)

1) Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Ensure uv is on PATH (installer prints what to add)
    # For zsh:
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    exec zsh

2) Create the project and environment
    mkdir phpbb-hasher && cd phpbb-hasher
    uv venv --python 3.13
    source .venv/bin/activate

3) Install dependency
    uv add argon2-cffi

4) Put the script in place
    # Save the Python script as phpbb_argon2.py in this folder
    chmod +x phpbb_argon2.py

## Usage

Generate a hash (prompted password):
    ./phpbb_argon2.py
Outputs a PHC string, e.g.:
    $argon2id$v=19$m=65536,t=6,p=1$BASE64SALT$BASE64HASH

Generate with explicit parameters:
    ./phpbb_argon2.py --variant id -t 6 -m 65536 -P 1 --hash-len 32 --salt-len 16

Verify a password against an existing hash:
    ./phpbb_argon2.py --verify '$argon2id$v=19$m=65536,t=6,p=1$BASE64SALT$BASE64HASH'
    # Prompts for password; prints "OK" or "FAIL"

Non-interactive input (CI / piping):
    printf '%s\n' 'supersecret' | ./phpbb_argon2.py --stdin
    ./phpbb_argon2.py --password 'supersecret'   # (less secure; shows in shell history)

## Defaults & Recommendations
- Variant: argon2id (recommended)
- Time cost (t): 6
- Memory cost (m): 65536 (KiB)
- Parallelism (p): 1
- Hash length: 32 bytes
- Salt length: 16 bytes

These are sane defaults and broadly compatible with phpBB3. Tune them to match your forum policy.

## Using the Hash in phpBB3
1. Back up your DB first.
2. Paste the generated PHC string into the `user_password` column for the target user in `phpbb_users`.
   Example SQL:
       UPDATE phpbb_users
       SET user_password = '$argon2id$v=19$m=65536,t=6,p=1$BASE64SALT$BASE64HASH'
       WHERE username = 'YourAdminName';
3. On the next login, phpBB/PHP’s `password_verify()` will accept it. If your phpBB config prefers a different cost, it may rehash automatically after a successful login—this is normal.

## Optional: Make it invocable via `uv run`
Create `pyproject.toml` in the same folder:

    [project]
    name = "phpbb-argon2"
    version = "0.1.0"
    requires-python = ">=3.13"
    dependencies = ["argon2-cffi"]

    [project.scripts]
    phpbb-argon2 = "phpbb_argon2:main"

Then you can run:
    uv run phpbb-argon2 --verify '$argon2id$...'

## Security Notes
- Prefer the interactive prompt or `--stdin` over `--password` (which can leak to shell history/process list).
- Store and transport hashes securely; treat them like credentials.
- Keep `argon2-cffi` up to date:
    uv sync --upgrade

## Troubleshooting
- ImportError: argon2
    Run `uv add argon2-cffi` (inside the venv) and try again.
- Wrong Python version
    Recreate the venv with `uv venv --python 3.13` and `source .venv/bin/activate`.
- Performance
    If generation is slow on older machines, reduce `-t` or `-m`. If too fast, increase them.

## License
MIT — provided as-is, no warranty.

## Example Layout
your-repo/
└── tools/
    ├── README.md      # ← this file
    └── phpbb_argon2.py
