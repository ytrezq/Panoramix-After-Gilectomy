#!/usr/bin/env python3
"""`make check`: tools/readability.py's rules on two small texts (the
readability check itself, `make readability`, runs over a corpus)."""
import os
import subprocess
import sys

tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools', 'readability.py')
sys.exit(subprocess.run([sys.executable, tool, 'selftest']).returncode)
