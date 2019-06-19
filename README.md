# lineparser
*lineparser* is a small library with one goal: parse fixed-width formatted files extremely quickly.
In order to achieve this, *lineparser* uses **Cython** to obtain the speed offered by good old
**C** code and the convenience of **Python**.

# Example

Since there is no comprehensive documentation for now, this example will have to suffice for now.
The files for this example can be found on the library's [github page](https://github.com/jkarns275/lineparser)

demo.py:
```python
import lineparser
import time

"""
Every fixed-width format file consists of a series of fixed-width fields on each and every line.
The lineparser library has you specify the format of your file by specifying which fields it has.

Fields are supplied as a list of tuples, in the order they appear in the file. Each tuple is a
pair with the type of the field first, then the number of columns that field occupies.
In this case the first field is a Float64 and occupies 12 columns, then a Float64 that occupies
10 columns, and so on. 

Here are some requirements for the fields:
- If your fields are not in the correct format, a FieldException will be raised. 
- You cannot have zero-width fields
- You cannot have zero fields
- You cannot have negative width fields (since is incoherent)


The total length of a line must match the sum of the columns occupied, so in this case each line
ought to take up exactly 80 characters, or else a LineParsingError will be thrown.

Right now, there are only 3 possible field types: Float64, String, and Int64. Int64 is not
pictured here, but is accessed the same way as the other two (i.e. lineparser.Int64).

The 3 fields types can also be referred to as str, float, and int.
"""

fields = [(lineparser.Float64, 12), (lineparser.Float64, 10), (lineparser.Float64, 12), 
        (lineparser.String, 6), (lineparser.String, 6), (lineparser.String, 14),
        (lineparser.String, 14), (lineparser.Float64, 6)]

try:
    start = time.time()
    
    # On a successfull parse, result will be a list of lists and numpy arrays (strings will be in 
    # lists, and numbers will be in numpy arrays). 
    result = lineparser.parse(fields, b'data/small_data.par')
    
    end = time.time()
    
    print(f"Took {end - start} seconds to parse")
except lineparser.LineParsingError as e:
    print(f"Encountered the following error while trying to parse:\n {str(e)}")

```

data/small_data.par
```
    31.43339 6.531E-28   31.442390     3     2       0.00048       0.00000   100
    41.89467 1.415E-26   62.878170     4     3       0.00065       0.00000   100
    41.89786 3.538E-27   62.876840     4     3       0.00064       0.00000   100
    ...
```

Running the example: `python3 demo.py`

# Building
*lineparser* is simple to build, and should only require one command:

```
$ python3 setup.py build
```

You should then be able to import it in a python interpreter (in the build directory):

```
$ python3 setup.py build
$ python3 
Python 3.6.7 (default, Oct 22 2018, 11:32:17)
[GCC 8.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import lineparser
>>> ...
```

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
