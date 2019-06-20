# -*- coding: utf-8 -*-
#cython: boundscheck=False, nonecheck=False, wraparound=False, cdivision=True, language_level=3
from libc.stdlib cimport malloc, free, strtol, strtod
from libc.stdio cimport fseek, fopen, fclose, ferror, ftell, fread, SEEK_END, SEEK_SET, FILE, printf
from libc.string cimport strncpy, strerror
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

cdef inline int parse_string(void *output, const char *str, long line_n, int field_len):
    cdef list loutput = <list> output
    cdef bytes copy = <bytes> str
    list.append(loutput, copy)
    return 0

cpdef enum Ty:
    Float64 = 0
    Int64 = 1
    String = 2
cdef int MAX_T = 2

ctypedef int (*ParseFn)(void *, const char *, long, int)

cdef ParseFn* parse_fn_map = [parse_f64, parse_i64, parse_string]

ctypedef struct CField:
    Ty ty
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

            if ty == Float64:
                res = parse_f64(output[j], t, line_n, fields[j].len)
            elif ty == Int64:
                res = parse_i64(output[j], t, line_n, fields[j].len)
            elif ty == String:
                res = parse_string(output[j], t, line_n, fields[j].len)

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

cdef ReadWholeFileResult read_whole_file(char *path):
    global errno
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

    cdef char *str = <char *> malloc(fsize + 1)
    if str == NULL:
        fclose(f)
        r.data = NULL
        r.data_len = 0
        r.err = OUT_OF_MEMORY
        return r

    # Either premature EOF or error; almost certainly NOT EOF though since we just checked
    # the length of the file
    if <long> fread(str, 1, fsize, f) != fsize:
        free(str)
        r = make_io_err(ferror(f))
        fclose(f)
        return r

    # Null terminate
    str[fsize] = 0

    fclose(f)
    r.data = str
    r.data_len = fsize
    r.err = 0
    return r

class LineParsingError(BaseException):

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
            if self.field_ty == Float64:
                return self.__err_location() + " Failed to parse Float64."
            elif self.field_ty == Int64:
                return self.__err_location() + " Failed to parse Int64."
        else:
            return f"error number {self.errno}"

class FieldError(BaseException):

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
    TODO
    """

    def __init__(self, ty, length):
        self.ty = self.__check_ty(ty)
        self.len = self.__check_len(length)

    def __check_ty(self, ty):
        if type(ty) == Ty:
            return ty

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

        raise FieldError(f"Invalid type specifier '{ty}'.")

    def __check_len(self, length):
        if type(length) != int:
            raise FieldError("Invalid field length type. Field length must be an int.")
        if length <= 0:
            raise FieldError("Invalid field length: must be greater than 0.")
        return length

    def to_cfield(self):
        cdef CField cf
        cf.ty = self.ty
        cf.len = self.len
        return cf


def parse(list pyfields, filename):
    """

    Attempts to parse the lines from `filename` using the field specfications supplied in `pyfields`.

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
        A list of numpy arrays and lists, where each index in the list corresponds to the field of
        the same index in the `pyfields` list. For String fields it will be a `list` of `str`, and
        for Float64 and Int64 it will be a numpy array.

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
    """
    # Ensure fields are properly formatted
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
        fields[i] = pyfields[i].to_cfield()

    # Calculate the length of one whole line
    cdef int linelen = 0
    for i in range(nfields):
        linelen += fields[i].len

    if type(filename) not in (str, bytes):
        raise TypeError(f"Argument 'filename' has incorrect type (expected str or bytes, got {type(filename)}")

    if type(filename) == str:
        filename = bytes(filename, encoding='utf8')

    cdef char *error = NULL
    cdef ReadWholeFileResult file_res = read_whole_file(bytes(filename))

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
        if fields[i].ty in (Float64, Int64):
            py_handles[i].resize(nlines)
        else:
            py_handles[i] = py_handles[i][0:nlines]
    free(fields)
    free(data)
    free(ptrs)

    return py_handles

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
    cdef int64_t[:] lptr
    cdef int32_t[:] iptr
    cdef Ty ty
    while i < nfields:
        ty = fields[i].ty
        if ty == Float64:
            arr = np.zeros(nlines, dtype=np.float64)
            py_handles.append(arr)
            dptr = arr
            ptrs[i] = <void *> &dptr[0]
        elif ty == Int64:
            arr = np.zeros(nlines, dtype=np.int64)
            py_handles.append(arr)
            lptr = arr
            ptrs[i] = <void *> &lptr[0]
        elif ty == String:
            arr = list()
            py_handles.append(arr)
            ptrs[i] = <void *> arr
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
