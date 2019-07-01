# -*- coding: utf-8 -*-
#cython: boundscheck=False, nonecheck=False, wraparound=False, cdivision=True, language_level=3
from libc.stdlib cimport malloc, free, strtol, strtod
from libc.stdio cimport fseek, fopen, fclose, ferror, ftell, fread, SEEK_END, SEEK_SET, FILE, printf
from libc.string cimport strncpy, strerror
from libc.stdint cimport int64_t, int32_t, int16_t, int8_t
from libc.errno cimport errno
import numpy as np
from libc.stdint cimport int32_t, int64_t

cdef int OUT_OF_MEMORY = 1
cdef int BAD_FIELDS = 2
cdef int BAD_LINE = 3
cdef int IO_ERROR = 4
cdef int PREMATURE_EOF = 5
cdef int PARSE_ERROR = 6

cdef inline int parse_f64(void *output, const char *str, long line_n, int field_len):
    global errno
    cdef double *doutput = <double *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    doutput[line_n] = strtod(str, &endptr);
    if errno != 0:
        errno = prev
        return 1
    if endptr - str < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0


cdef inline int parse_f32(void *output, const char *str, long line_n, int field_len):
    global errno
    cdef float *foutput = <float *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    foutput[line_n] = <float> strtod(str, &endptr);
    if errno != 0:
        errno = prev
        return 1
    if endptr - str < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0

cdef inline int parse_i64(void *output, const char *st, long line_n, int field_len):
    global errno
    cdef int64_t *ioutput = <int64_t *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    ioutput[line_n] = strtol(st, &endptr, 10)
    if errno != 0:
        errno = prev
        return 1
    if endptr - st < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0

cdef inline int parse_i32(void *output, const char *st, long line_n, int field_len):
    global errno
    cdef int32_t *ioutput = <int32_t *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    ioutput[line_n] = <int32_t> strtol(st, &endptr, 10)
    if errno != 0:
        errno = prev
        return 1
    if endptr - st < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0

cdef inline int parse_i16(void *output, const char *st, long line_n, int field_len):
    global errno
    cdef int16_t *ioutput = <int16_t *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    ioutput[line_n] = <int16_t> strtol(st, &endptr, 10)
    if errno != 0:
        errno = prev
        return 1
    if endptr - st < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0

cdef inline int parse_i8(void *output, const char *st, long line_n, int field_len):
    global errno
    cdef int8_t *ioutput = <int8_t *> output
    cdef int prev = errno
    cdef char *endptr
    cdef char c
    errno = 0
    ioutput[line_n] = <int8_t> strtol(st, &endptr, 10)
    if errno != 0:
        errno = prev
        return 1
    if endptr - st < field_len:
        c = endptr[0]
        # If the parser ended on something other than a space, there is probably an issue
        if c not in [b' ', b'\n', b'\r']:
            return 1
    errno = prev
    return 0

cdef inline int parse_bytes(void *output, const char *str, long line_n, int field_len):
    cdef list loutput = <list> output
    cdef bytes copy = <bytes> str
    list.append(loutput, copy)
    return 0

cdef inline int parse_string(void *output, const char *s, long line_n, int field_len):
    cdef list loutput = <list> output
    cdef str copy = s[:field_len].decode('UTF-8')
    list.append(loutput, copy)
    return 0

cdef inline int parse_phantom(void *output, const char *s, long line_n, int field_len):
    return 0


cdef enum CTy:
    Float64 = 0
    Float32 = 1
    Int64 = 2
    Int32 = 3
    Int16 = 4
    Int8 = 5
    String = 6
    Phantom = 7
    Bytes = 8

ctypedef int (*ParseFn)(void *, const char *, long, int)
ctypedef void (*InnerParseFn)(void *, const char *, long, int, char **)
cdef ParseFn *PARSE_FN_MAP = [
    &parse_f64,
    &parse_f32,
    &parse_i64,
    &parse_i32,
    &parse_i16,
    &parse_i8,
    &parse_string,
    &parse_phantom,
    &parse_bytes,
]

from enum import IntEnum
class Ty(IntEnum):
    """
    An enumeration for the valid field types.
    
    - Float types are real numbers.
    - Int types are signed integers.
    - The string type is a string.
    - The phantom type is ... nothing. If there is a field in a file you don't need, instead of
        parsing it and wasting time and memory, use the Phantom type. This will completely
        ignore the fields contents.

    When choosing a data type, it is important to ensure that the numbers you will be reading can
    fit into the data type. For example, Int8 can hold numbers from -128 to 127. If your field has
    numbers between -1000 and 5000, than Int8 is going to be the wrong data type. Int16, Int32, and
    Int64 would all be acceptable choices, but Int16 may be consided optimal since it would
    consume the least amount of ram.

    For more information pertaining data type ranges / capacities, refer to the numpy data types
    documentation.
    
    """
    Float64 = 0
    Float32 = 1
    Int64 = 2
    Int32 = 3
    Int16 = 4
    Int8 = 5
    String = 6
    Phantom = 7
    Bytes = 8

cdef int MAX_T = 8

def ty_to_str(ty):
    if ty == Float64:
        return "Float64"
    elif ty == Float32:
        return "Float32"
    elif ty == Int64:
        return "Int64"
    elif ty == String:
        return "String"
    elif ty == Phantom:
        return "Phantom"
    elif ty == Int32:
        return "Int32"
    elif ty == Int16:
        return "Int16"
    elif ty == Int8:
        return "Int8"
    elif ty == Bytes:
        return "Bytes"
    else:
        raise Exception(f"{ty} is not a valid Ty")



ctypedef struct CField:
    CTy ty
    int len

ctypedef struct NextLineResult:
    char *line
    int err


cdef char LF = 10
cdef char CR = 13

cdef NextLineResult fast_next_line(char* current_position, char* end_position, int line_len):
    cdef char *new_pos = current_position + line_len
    cdef NextLineResult r
    r.line = NULL
    r.err = 0

    if new_pos >= end_position:
        return r

    cdef char c = new_pos[0]

    # Lines should end with newline or null; if not, there is probably a bad line
    if c not in [LF, CR, 0]:
        r.line = NULL
        r.err = BAD_LINE
        return r
    new_pos += 1
    while True:
        c = new_pos[0]

        if c == LF or c == CR:
            new_pos += 1
        elif c == 0:
            if new_pos != end_position:
                r.err = PREMATURE_EOF
                r.line = NULL
            else:
                r.line = NULL
                r.err = 0
            return r
        else:
            r.line = new_pos
            return r


ctypedef struct FastParseResult:
    # error code
    int err

    # line number with the error on it (base 0, i.e. not human readable line number)
    long line_n

    # if there was a parse error, this will have the field index of the error, otherwise -1
    int field_index


cdef FastParseResult fast_parse_internal(char *data, long data_len, long max_nlines, int line_len, CField *fields, void **output, int nfields):
    cdef long line_n = 0
    cdef char *end = data + data_len
    cdef char *t = NULL
    cdef int length = 0, j = 0
    cdef char temp = 0
    cdef int res = 0
    cdef FastParseResult pr
    cdef NextLineResult nlr
    nlr.line = data
    nlr.err = 0

    while nlr.line != NULL:
        j = 0
        length = 0
        while j < nfields:
            t = &nlr.line[length]
            length += fields[j].len
            temp = nlr.line[length]
            nlr.line[length] = 0
            ty = fields[j].ty
            
            # Seems like using function pointers is slower than the jump table generated
            # by the if statement
            # res = (PARSE_FN_MAP[<int> ty])(output[j], t, line_n, fields[j].len)

            if ty == Float64:
                res = parse_f64(output[j], t, line_n, fields[j].len)
            elif ty == Float32:
                res = parse_f32(output[j], t, line_n, fields[j].len)
            elif ty == Int64:
                res = parse_i64(output[j], t, line_n, fields[j].len)
            elif ty == Int32:
                res = parse_i32(output[j], t, line_n, fields[j].len)
            elif ty == Int16:
                res = parse_i16(output[j], t, line_n, fields[j].len)
            elif ty == Int8:
                res = parse_i8(output[j], t, line_n, fields[j].len)
            elif ty == String:
                res = parse_string(output[j], t, line_n, fields[j].len)
            elif ty == Bytes:
                res = parse_bytes(output[j], t, line_n, fields[j].len)
            elif ty == Phantom:
                pass

            if res != 0:
                pr.err = PARSE_ERROR
                pr.field_index = j
                pr.line_n = line_n
                return pr

            j += 1
            nlr.line[length] = temp

        nlr = fast_next_line(nlr.line, end, line_len)
        line_n += 1

    if nlr.err != 0:
        pr.err = nlr.err
        pr.line_n = line_n
        pr.field_index = -1
    else:
        pr.err = 0
        pr.line_n = line_n
        pr.field_index = -1

    return pr

ctypedef struct ReadWholeFileResult:
    long data_len
    char *data
    int err
    int io_err

cdef ReadWholeFileResult make_io_err(int io_err):
    cdef ReadWholeFileResult r
    r.data_len = 0
    r.data = NULL
    r.err = IO_ERROR
    r.io_err = io_err
    return r

cdef ReadWholeFileResult read_whole_file(object filename):
    global errno

    if type(filename) not in (str, bytes):
        raise TypeError(f"Argument 'filename' has incorrect type (expected str or bytes, " \
                         "got {type(filename)})")

    if type(filename) == str:
        filename = bytes(filename, encoding='utf8')
    
    cdef char *path = filename
    cdef int prev = errno
    cdef ReadWholeFileResult r

    cdef FILE *f = fopen(path, "rb")

    # file couldnt be opened
    if f == NULL:
        r = make_io_err(errno)
        errno = prev
        return r

    errno = prev

    if fseek(f, 0, SEEK_END) != 0:
        r = make_io_err(ferror(f))
        fclose(f)
        return r

    cdef long fsize = <long> ftell(f)
    if fseek(f, 0, SEEK_SET) != 0:
        r = make_io_err(ferror(f))
        fclose(f)
        return r

    cdef char *data = <char *> malloc(fsize + 1)
    if data == NULL:
        fclose(f)
        r.data = NULL
        r.data_len = 0
        r.err = OUT_OF_MEMORY
        return r

    # Either premature EOF or error; almost certainly NOT EOF though since we just checked
    # the length of the file
    if <long> fread(data, 1, fsize, f) != fsize:
        free(data)
        r = make_io_err(ferror(f))
        fclose(f)
        return r

    # Null terminate
    data[fsize] = 0

    fclose(f)
    r.data = data
    r.data_len = fsize
    r.err = 0
    return r

class LineParsingError(BaseException):
    """

    This error occurs when something goes wrong during parsing. This includes the following:
    - A malformed line: a line is either too long or too short.
    - Premature end of file: the last line is shorter than expected
    - Failure to parse Int64: an invalid Int64 string was encountered where there should have been
    a valid Int64 string.
    - Failure to parse Float64: an invalid was encountered where there should have been a valid
    Float64 string.

    Examples
    --------
    >>> from lineparser import NamedField, named_parse, \ 
    ...                        LineParsingError
    >>> fields = [NamedField("a", int, 3), 
    ...           NamedField("b", int, 4), 
    ...           NamedField("c", str, 6)]
    >>> file = open("test.lines", "w")
    >>> file.write(" 15 255 dog\\n") #
    12
    >>> file.write("146  12 horse\\n")
    14
    >>> file.close()
    >>> try:
    ...     named_parse(fields, "test.lines")
    ... except LineParsingError as e:
    ...     print(f"Encountered error: {e}")
    ...
    Encountered error: test.lines:2:0: Encountered a malformed line.
    >>>


    
    """

    def __init__(self, errno, line_n, field_ty, field_pos, filename):
        self.errno = errno
        self.field_ty = field_ty
        self.field_pos = field_pos
        self.line_n = line_n
        self.field_pos = field_pos
        self.filename = filename

    def __err_location(self):
        return f"{self.filename}:{self.line_n + 1}:{self.field_pos + 1}:"

    def __str__(self):
        if self.errno == 1:
            return f"Ran out of memory while trying to parse file '{self.filename}'. " + \
                    "The file you supplied may be too big for your computer to handle."
        elif self.errno == BAD_FIELDS:
            return f"You shouldn't see this"
        elif self.errno == BAD_LINE:
            return  self.__err_location() + " Encountered a malformed line."
        elif self.errno == IO_ERROR:
            return "You shouldn't see this"
        elif self.errno == PREMATURE_EOF:
            return self.__err_location() + " Encountered unexpected end of file. " + \
                    "Is your last line malformed?"
        elif self.errno == PARSE_ERROR:
            return self.__err_location() + f" Failed to parse {ty_to_str(self.ty)}."
        else:
            return f"error number {self.errno}"

class FieldError(BaseException):
    """

    A FieldError is raised when there is something wrong with a Field or NamedField. The error
    just contains a short description of what the problem was. Possible errors include:
    
    - Invalid field type.
    - Invalid field length (length must be > 0)
    - Passing an object that is not of type `Field` as the field lists
    - Having zero fields

    """

    def __init__(self, err):
        self.err = err

    def __str__(self):
        return str(self.err)


class Field:
    """
    Creates a new `Field`, and verifies that the supplied `ty` and `length` parameters are of
    of the appropriate type.

    Parameters
    ----------
    ty : `Ty` or int or `type`
        The field type. Must be an integer which corresponds to Ty. You can also use the the 'int',
        'float', and 'str' type classes.
    length : int
        The length of the field. This must be a positive integer.

    Examples
    --------
    >>> import lineparser
    >>> lineparser.Field(str, 5)
    Field(String, 5)
    >>> lineparser.Field(int, 10)
    Field(Int64, 10)
    >>> lineparser.Field(float, 6)
    Field(Float64, 6)
    >>> lineparser.Field(lineparser.Float64, 14)
    Field(Float64, 14)

    """

    def __init__(self, ty, length):
        self.ty = self.__check_ty(ty)
        self.len = self.__check_len(length)

    def __check_ty(self, ty):
        if type(ty) == Ty:
            return int(ty)

        if type(ty) == int:
            if ty > MAX_T or ty < 0:
                raise FieldError(f"Invalid type id {ty}, type ids must be between 0 and {MAX_T}.")
            return ty

        if ty == int:
            return Int64
        elif ty == float:
            return Float64
        elif ty == str:
            return String
        elif ty == bytes:
            return Bytes

        raise FieldError(f"Invalid type specifier '{ty}'.")

    def __check_len(self, length):
        if type(length) != int:
            raise FieldError("Invalid field length type. Field length must be an int.")
        if length <= 0:
            raise FieldError("Invalid field length: must be greater than 0.")
        return length

    def _to_cfield(self):
        cdef CField cf
        cf.ty = self.ty
        cf.len = self.len
        return cf

    def __str__(self):
        return f"Field({ty_to_str(self.ty)}, {self.len})"
    def __repr__(self):
        return str(self)

cdef CField *make_fields(list pyfields):
    if len(pyfields) == 0:
        raise FieldError("Cannot have zero fields.")

    for field in pyfields:
        if type(field) != Field:
            raise FieldError("Invalid fields lists. All elements of the list must be of type 'Field'.")

    cdef int nfields = len(pyfields)
    cdef CField *fields = <CField *> malloc(sizeof(CField) * nfields)

    # Unlikely but theres no reason not to check
    if fields == NULL:
        raise MemoryError("There is not enough memory to allocate the fields.")

    # Move them to C structs
    for i in range(nfields):
        fields[i] = pyfields[i]._to_cfield()
    
    return fields

def parse(list pyfields, filename):
    """

    Attempts to parse the lines from `filename` using the field specfications supplied in `pyfields`

    Parameters
    ----------
    pyfields : `list` of Field
        This list describes the fixed-width file format. The Fields in the list ought to be in the
        same order that they appear in the file.
    filename : `str` or `bytes`
        The filename or path which points to the fixed-width formatted file. If filename is a `str`,
        it must be utf-8 encoded

    Returns
    -------
    `list` of iterable
        A list of numpy arrays and lists, where the order matches that of the fields supplied in
        `pyfields`. For String fields it will be a `list` of `str`, and for Float64 and Int64 it
        will be a numpy array.

    Raises
    ------
    LineParsingError
        If there is a bad line (wrong length), or a bad field (failed to parse)
    OSError
        If this function fails to open `filename`
    FieldError
        If there are zero fields provided, or if the provided fields are not all of type `Field`
    MemoryError
        If there is not enough memory to read the input file and allocate field containers.

    Examples
    --------
    >>> from lineparser import parse, Field
    >>> fields = [Field(int, 3), 
    ...           Field(int, 4), 
    ...           Field(str, 6)]
    >>> file = open("test.lines", "w")
    >>> file.write(" 15 255   dog\\n")
    14
    >>> file.write("146  12 horse\\n")
    14
    >>> file.close()
    >>> parse(fields, "test.lines")
    [array([ 15, 146]), 
     array([255,  12]), 
     [b'   dog', b' horse']]    

    """
    cdef int nfields = len(pyfields)
    cdef CField *fields = make_fields(pyfields)

    # Calculate the length of one whole line
    cdef int linelen = 0
    for i in range(nfields):
        linelen += fields[i].len

    cdef char *error = NULL
    cdef ReadWholeFileResult file_res = read_whole_file(filename)

    if file_res.err != 0:
        if file_res.err == OUT_OF_MEMORY:
            raise MemoryError("There is not enough memory to read the entire input file.")

        error = strerror(file_res.err)
        raise OSError(file_res.err, str(error))

    cdef char *data = file_res.data
    cdef long data_len = file_res.data_len
    cdef long max_lines = data_len / linelen

    cdef AllocationResult output_obj = allocate_field_outputs(fields, nfields, max_lines)

    if output_obj is None:
        raise Exception("Failed to allocate output: out of memory.")

    cdef void **ptrs = output_obj.ptrs
    cdef FastParseResult pr = \
            fast_parse_internal(data, data_len, max_lines, linelen, fields, output_obj.ptrs, nfields)

    cdef int field_pos = -1
    
    if pr.err != 0:
        field_ty = None
        if pr.field_index != -1:
            field_pos = 0
            field_ty = fields[pr.field_index].ty
            for i in range(pr.field_index):
                field_pos += fields[i].len

        free(data)
        free(fields)
        free(ptrs)

        raise LineParsingError(pr.err, pr.line_n, field_ty, field_pos, str(filename))

    cdef list py_handles = output_obj.py_handles

    nlines = pr.line_n

    for i in range(nfields):
        if fields[i].ty == Phantom:
            continue
        if fields[i].ty in (Float64, Float32, Int64, Int32, Int16, Int8):
            py_handles[i].resize(nlines)
        else:
            py_handles[i] = py_handles[i][0:nlines]
    
    # Remove 'Nones' from py_handles (cause by Phantom fields)
    py_handles = list(filter(lambda p: p is not None, py_handles))
    
    free(fields)
    free(data)
    free(ptrs)

    return py_handles

class DuplicateFieldNameError(Exception):

    def __init__(self, name):
        self.name = name

    def __str__(self):
        return f"Duplicate field name '{self.name}'."


def named_parse(list named_fields, filename):
    """

    Attempts to parse the lines from `filename` using the field specfications supplied in
    `named_fields`. Then, a map is created where the keys are the supplied names, and the values
    are the results of parsing.

    Parameters
    ----------
    named_fields : `list` of NamedField
        This list describes the fixed-width file format. The Fields in the list ought to be in the
        same order that they appear in the file.
    filename : `str` or `bytes`
        The filename or path which points to the fixed-width formatted file. If filename is a `str`,
        it must be utf-8 encoded

    Returns
    -------
    `list` of iterable
        A map from name to the result of parsing, where the parsing results are either a list or
        a numpy array. For String fields it will be a `list` of `str`, and for Float64 and Int64 it
        will be a numpy array.

    Raises
    ------
    LineParsingError
        If there is a bad line (wrong length), or a bad field (failed to parse)
    OSError
        If this function fails to open `filename`
    FieldError
        If there are zero fields provided, or if the provided fields are not all of type `Field`
    MemoryError
        If there is not enough memory to read the input file and allocate field containers.
    DuplicateFieldNameError
        If more than two or more of the NamedFields in `named_field` have the same name.

    Examples
    --------
    >>> from lineparser import named_parse, NamedField
    >>> fields = [NamedField("a", int, 3), 
    ...           NamedField("b", int, 4), 
    ...           NamedField("c", str, 6)]
    >>> file = open("test.lines", "w")
    >>> file.write(" 15 255   dog\\n")
    14
    >>> file.write("146  12 horse\\n")
    14
    >>> file.close()
    >>> named_parse(fields, "test.lines")
    { 'a': array([ 15, 146]), 
      'b': array([255,  12]), 
      'c': [b'   dog', b' horse']
    }


    """
    names = set()
    for field in named_fields:
        if field.name in names:
            raise DuplicateFieldNameError(field.name)
        names.add(field.name)

    fields = list(map(lambda named_field: named_field.field, named_fields))

    parsed = parse(fields, filename)

    named_result = {}

    non_phantom_fields = list(filter(lambda p: p is not None, named_fields))
    for (named_field, result) in zip(non_phantom_fields, parsed):
        named_result[named_field.name] = result
    
    return named_result

class NamedField:
    """
    The NamedField class is just like the field class, except it has a name.

    Parameters
    ---------
    name : `str`
        The name of the field. This name should be unique.
    ty : `Ty` or int or `type`
        The type of the field. This can be an instance of the `Ty` enumeration, or one of the type
        literals 'int', 'float', and 'str'.
    length : int
        The length of the field. This must be a positive integer.
    
    Examples
    --------
    >>> from lineparser import NamedField
    >>> NamedField("f1", float, 10)
    NamedField('f1', Float64, 10)
    >>> NamedField("f2", str, 4)
    NamedField('f2', String, 4)
    >>> NamedField("f3", int, 8)
    NamedField('f3', Int64, 8)
    >>> p = NamedField("p", str, 25)
    >>> p.field
    Field(String, 25)
    >>> p.name
    'p'
    >>> p.field.len
    25
    >>> p.field.ty
    2

    """

    def __init__(self, name, ty, length):
        self.field = Field(ty, length)
        self.name = self.__check_name(name)

    def __check_name(self, name):
        if type(name) not in (str, bytes):
            raise TypeError(f"name should be of type str or bytes, instead got {type(name)}")
        return name

    def __str__(self):
        return f"NamedField({repr(self.name)}, {ty_to_str(self.field.ty)}, {self.field.len})"

    def __repr__(self):
        return str(self)



cdef class AllocationResult:
    cdef void **ptrs
    cdef object py_handles


cdef AllocationResult allocate_field_outputs(const CField *fields, int nfields, long nlines):
    """
    Allocates output based on the field specifications. The only data type that doesn't get an
    an array for output is string, since c strings don't mix with python very well; so to minimize
    copies a python list will be hold the python strings.

    :return: [] if any of the fields have an invalid type, otherwise returns
    [py_handles, <ptrs>] where py_handles contains python objects which contain the output data,
    and <ptrs> is a c array of pointers to the output containers
    """
    cdef list py_handles = []
    cdef void **ptrs = <void**> malloc(sizeof(void*) * nfields)
    cdef int i = 0
    cdef double[:] dptr
    cdef float[:] fptr
    cdef int64_t[:] lptr
    cdef int32_t[:] iptr
    cdef int16_t[:] sptr
    cdef int8_t[:] bptr
    cdef CTy ty
    while i < nfields:
        ty = fields[i].ty
        if ty == Float64:
            arr = np.zeros(nlines, dtype=np.float64)
            py_handles.append(arr)
            dptr = arr
            ptrs[i] = <void *> &dptr[0]
        elif ty == Float32:
            arr = np.zeros(nlines, dtype=np.float32)
            py_handles.append(arr)
            fptr = arr
            ptrs[i] = <void *> &fptr[0]
        elif ty == Int64:
            arr = np.zeros(nlines, dtype=np.int64)
            py_handles.append(arr)
            lptr = arr
            ptrs[i] = <void *> &lptr[0]
        elif ty == Int32:
            arr = np.zeros(nlines, dtype=np.int32)
            py_handles.append(arr)
            iptr = arr
            ptrs[i] = <void *> &iptr[0]
        elif ty == Int16:
            arr = np.zeros(nlines, dtype=np.int16)
            py_handles.append(arr)
            sptr = arr
            ptrs[i] = <void *> &sptr[0]
        elif ty == Int8:
            arr = np.zeros(nlines, dtype=np.int8)
            py_handles.append(arr)
            bptr = arr
            ptrs[i] = <void *> &bptr[0]
        elif ty in (String, Bytes):
            arr = list()
            py_handles.append(arr)
            ptrs[i] = <void *> arr
        elif ty == Phantom:
            arr = None
            py_handles.append(None)
            ptrs[i] = NULL
        else:
            free(ptrs)
            ar = AllocationResult()
            ar.ptrs = NULL
            ar.py_handles = None
            return ar
        i += 1

    ar = AllocationResult()
    ar.ptrs = ptrs
    ar.py_handles = py_handles

    return ar
