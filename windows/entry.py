import multiprocessing
import os
import sys

if __name__ == '__main__':
    multiprocessing.freeze_support()
    if os.path.basename(sys.executable).lower() == 'constant-watch.exe' and len(sys.argv) == 1:
        from constant_watch.windows_desktop import main
        main()
    else:
        from constant_watch.cli import main
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
