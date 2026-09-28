"""Standalone entry point for the bundled service and stdio MCP server."""
import multiprocessing
import os
import sys
from constant_watch.cli import main

if __name__ == "__main__":
    multiprocessing.freeze_support()
    # The MCP transport wraps and eventually closes stream buffers. Give it
    # duplicate descriptors so the frozen bootloader can flush its original
    # sys.__stdout__ on exit without writing to a closed file.
    originals = (sys.stdin, sys.stdout)
    duplicates = []
    if sys.argv[1:2] == ['mcp']:
        duplicates = [open(os.dup(sys.stdin.fileno()), 'r', encoding='utf-8'),
                      open(os.dup(sys.stdout.fileno()), 'w', encoding='utf-8', buffering=1)]
        sys.stdin, sys.stdout = duplicates
    try:
        main()
    finally:
        sys.stdin, sys.stdout = originals
        for stream in duplicates:
            if not stream.closed:
                stream.close()
