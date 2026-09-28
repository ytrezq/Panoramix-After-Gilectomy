"""pip install . - the python module panoramix_asm, built by the Makefile
(which needs as, cc, libgmp and liblzma: the module is the assembly
library and a thin CPython wrapper)."""
import os
import shutil
import subprocess
import sys
import sysconfig

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext

HERE = os.path.dirname(os.path.abspath(__file__))


class MakeBuild(build_ext):
    """the extension made by `make`, for the python running this"""

    def build_extension(self, ext):
        suffix = sysconfig.get_config_var("EXT_SUFFIX")
        target = "build/panoramix_asm" + suffix
        subprocess.check_call(["make", "-j4", "PYTHON=" + sys.executable, target], cwd=HERE)
        dest = self.get_ext_fullpath(ext.name)
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        shutil.copy(os.path.join(HERE, target), dest)


setup(
    name="panoramix-asm",
    version="0.1.0",
    description="The panoramix EVM decompiler, in x86-64 assembly",
    long_description=open(os.path.join(HERE, "README.md")).read(),
    long_description_content_type="text/markdown",
    ext_modules=[Extension("panoramix_asm", sources=[])],
    cmdclass={"build_ext": MakeBuild},
    python_requires=">=3.8",
)
