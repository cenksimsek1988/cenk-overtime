"""Test helper for test-deliver.sh: make or remove a linked folder.

    python make-link.py TARGET LINK      a symbolic link, or a junction on Windows
    python make-link.py --remove LINK    remove the link, never its target

Exit 1 when this system lets the test make neither kind.
"""
import os
import sys


def main(argv):
    if len(argv) == 2 and argv[0] == "--remove":
        link = argv[1]
        try:
            os.unlink(link)   # a symbolic link
        except OSError:
            os.rmdir(link)    # a junction: removes the link only
        return 0
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    target, link = argv
    try:
        os.symlink(target, link, target_is_directory=True)
        return 0
    except (OSError, NotImplementedError):
        pass
    try:
        import _winapi
        _winapi.CreateJunction(target, link)
        return 0
    except (ImportError, AttributeError, OSError):
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
