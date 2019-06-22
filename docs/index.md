---
layout: default
title: Home
---
# *lineparser*
*lineparser* is a small library with one goal: parse fixed-width formatted files extremely quickly.
In order to achieve this, *lineparser* uses **Cython** to obtain the speed offered by good old
**C** code and the convenience of **Python**.

# Installing
You should be able to install *lineparser* via pip if you are on a Windows or Linux 64 bit machine.

```
$ pip3 install lineparser
```

## Installing from Source
Installing from source is also easy. You must have GCC installed on your machine, and you must have
**Cython** installed only if you want to modify the library. Then run this command:

```
$ python3 setup.py install
```

You may need root / administrator privileges to install.

# Example

`demo.py`
```python
from lineparser import Field, parse
import time

fields = [  Field(float, 12),
            Field(float, 10), 
            Field(float, 12), 
            Field(str, 6),
            Field(str, 6),
            Field(str, 14),
            Field(str, 14),
            Field(float, 6) ]

try:
    start = time.time()
    
    lines = parse(fields, b'data/small_data.par')
    
    end = time.time()
    
    print(f"Took {end - start} seconds to parse")
except Exception as e:
    print(f"Encountered an error:\n {str(e)}")

# Use lines

```

`data/small_data.par`
```
    31.43339 6.531E-28   31.442390     3     2       0.00048       0.00000   100
    41.89467 1.415E-26   62.878170     4     3       0.00065       0.00000   100
    41.89786 3.538E-27   62.876840     4     3       0.00064       0.00000   100
    ...
```

Running the example: `python3 demo.py`