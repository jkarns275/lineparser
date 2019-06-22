from setuptools import setup
from setuptools.extension import Extension

def should_use_cython():
    try:
        import Cython
        return True
    except:
        return False

USE_CYTHON = should_use_cython()

ext = '.pyx' if USE_CYTHON else '.c'

extensions = [Extension("lineparser", ["src/lineparser" + ext])]

if USE_CYTHON:
    from Cython.Build import cythonize
    extensions = cythonize(extensions)
    
    for e in extensions:
        e.cython_directives = {"embedsignature": True}

with open("README.md", "r") as f:
    long_description = f.read()

setup(  name="lineparser",
        version="0.0.0.dev2",
        author="Joshua Karns",
        author_email="jkarns275@gmail.com",
        description="Fast parser for fixed-column line data files",
        long_description=long_description,
        long_description_content_type="text/markdown",
	url="https://github.com/jkarns275/lineparser",
        license='MIT',
        classifiers=[
            'Development Status :: 3 - Alpha',
            'License :: OSI Approved :: MIT License',
            'Programming Language :: Python :: 3'
        ],
        ext_modules=extensions)
