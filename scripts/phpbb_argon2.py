#!/usr/bin/env python3
"""
phpbb_argon2.py — Generate or verify phpBB3-compatible Argon2 password hashes.

Examples:
  Generate (prompted password):
    python phpbb_argon2.py

  Generate with explicit params:
    python phpbb_argon2.py --variant id -t 6 -m 65536 -P 1 --hash-len 32 --salt-len 16

  Verify:
    python phpbb_argon2.py --verify '$argon2id$v=19$m=65536,t=6,p=1$BASE64SALT$BASE64HASH'
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys

try:
    from argon2.low_level import (
        Type,
        hash_secret,
        verify_secret,
    )
except ImportError as e:
    print("Missing dependency: argon2-cffi. See setup instructions below.", file=sys.stderr)
    raise

def _variant_to_type(variant: str) -> Type:
    v = variant.lower()
    if v == "id":
        return Type.ID
    if v == "i":
        return Type.I
    raise ValueError(f"Unsupported variant: {variant} (use 'id' or 'i')")

def generate_hash(
    password: str,
    *,
    variant: str = "id",
    time_cost: int = 6,
    memory_cost: int = 65536,  # KiB
    parallelism: int = 1,
    hash_len: int = 32,
    salt_len: int = 16,
) -> str:
    """Return PHC-encoded Argon2 hash string."""
    salt = os.urandom(salt_len)
    t = _variant_to_type(variant)
    encoded: bytes = hash_secret(
        secret=password.encode("utf-8"),
        salt=salt,
        time_cost=time_cost,
        memory_cost=memory_cost,
        parallelism=parallelism,
        hash_len=hash_len,
        type=t,
        version=19,
    )
    return encoded.decode("utf-8")

def verify_hash(password: str, encoded_hash: str, *, variant: str = "id") -> bool:
    """Verify password against a PHC-encoded Argon2 hash string."""
    t = _variant_to_type(variant)
    try:
        return verify_secret(encoded_hash.encode("utf-8"), password.encode("utf-8"), type=t)
    except Exception:
        return False

def main() -> int:
    parser = argparse.ArgumentParser(description="Generate or verify phpBB3-compatible Argon2 hashes.")
    mode = parser.add_mutually_exclusive_group(required=False)
    mode.add_argument("--verify", metavar="HASH", help="Verify the entered password against this PHC hash string.")
    parser.add_argument("--variant", choices=["id", "i"], default="id",
                        help="Argon2 variant: 'id' (recommended/default) or 'i'.")
    parser.add_argument("-t", "--time-cost", type=int, default=6, help="Iterations (time cost). Default: 6")
    parser.add_argument("-m", "--memory-cost", type=int, default=65536, help="Memory cost in KiB. Default: 65536")
    parser.add_argument("-P", "--parallelism", type=int, default=1, help="Parallelism (lanes/threads). Default: 1")
    parser.add_argument("--hash-len", type=int, default=32, help="Hash length (bytes). Default: 32")
    parser.add_argument("--salt-len", type=int, default=16, help="Salt length (bytes). Default: 16")
    parser.add_argument("--password", help="Password (NOT recommended; use prompt).")
    parser.add_argument("--stdin", action="store_true", help="Read password from STDIN (single line).")

    args = parser.parse_args()

    # Get password
    if args.password is not None:
        pwd = args.password
    elif args.stdin:
        pwd = sys.stdin.readline().rstrip("\n")
    else:
        pwd = getpass.getpass("Password: ")

    if args.verify:
        ok = verify_hash(pwd, args.verify, variant=args.variant)
        print("OK" if ok else "FAIL")
        return 0 if ok else 1

    encoded = generate_hash(
        pwd,
        variant=args.variant,
        time_cost=args.time_cost,
        memory_cost=args.memory_cost,
        parallelism=args.parallelism,
        hash_len=args.hash_len,
        salt_len=args.salt_len,
    )
    print(encoded)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
