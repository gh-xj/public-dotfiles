#!/usr/bin/env python3
"""Compare allocated bytes with APFS private bytes for files or directory trees."""

import argparse
import ctypes
import os
from pathlib import Path
import struct
import sys


ATTR_BIT_MAP_COUNT = 5
ATTR_CMNEXT_PRIVATESIZE = 0x00000008
FSOPT_NOFOLLOW = 0x00000001
FSOPT_REPORT_FULLSIZE = 0x00000004
FSOPT_ATTR_CMN_EXTENDED = 0x00000020


class AttrList(ctypes.Structure):
    _fields_ = [
        ("bitmapcount", ctypes.c_ushort),
        ("reserved", ctypes.c_ushort),
        ("commonattr", ctypes.c_uint32),
        ("volattr", ctypes.c_uint32),
        ("dirattr", ctypes.c_uint32),
        ("fileattr", ctypes.c_uint32),
        ("forkattr", ctypes.c_uint32),
    ]


LIBC = ctypes.CDLL(None, use_errno=True)
LIBC.getattrlist.argtypes = [ctypes.c_char_p, ctypes.POINTER(AttrList), ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong]
LIBC.getattrlist.restype = ctypes.c_int


def private_size(path):
    attributes = AttrList(ATTR_BIT_MAP_COUNT, 0, 0, 0, 0, 0, ATTR_CMNEXT_PRIVATESIZE)
    buffer = ctypes.create_string_buffer(12)
    options = FSOPT_NOFOLLOW | FSOPT_REPORT_FULLSIZE | FSOPT_ATTR_CMN_EXTENDED
    if LIBC.getattrlist(os.fsencode(path), ctypes.byref(attributes), buffer, len(buffer), options) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), os.fspath(path))
    length = struct.unpack_from("=I", buffer.raw, 0)[0]
    if length < 12:
        raise OSError(f"private-size response was only {length} bytes for {path}")
    return struct.unpack_from("=Q", buffer.raw, 4)[0]


def entries(path):
    yield path
    if path.is_dir() and not path.is_symlink():
        for directory, names, files in os.walk(path, followlinks=False):
            root = Path(directory)
            for name in names + files:
                yield root / name


def tree_size(path):
    allocated = 0
    private = 0
    seen = set()
    for entry in entries(path):
        stat = entry.lstat()
        identity = (stat.st_dev, stat.st_ino)
        if identity in seen:
            continue
        seen.add(identity)
        allocated += stat.st_blocks * 512
        private += private_size(entry)
    return allocated, private


def human(value):
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    number = float(value)
    for unit in units:
        if number < 1024 or unit == units[-1]:
            return f"{number:.0f}{unit}" if unit == "B" else f"{number:.1f}{unit}"
        number /= 1024
    raise AssertionError("unreachable")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bytes", action="store_true", help="print exact byte counts instead of human-readable sizes")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    print("allocated\tprivate\tpath")
    for path in args.paths:
        try:
            allocated, private = tree_size(path)
            formatter = str if args.bytes else human
            print(f"{formatter(allocated)}\t{formatter(private)}\t{path}")
        except OSError as error:
            failed = True
            print(f"apfs-size: {error}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
