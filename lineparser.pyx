#cython: boundscheck=False, nonecheck=False, wraparound=False, cdivision=True
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
        if c not in [' ', '\n', '\r']:
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
        if c not in [' ', '\n', '\r']:
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

ctypedef struct Field:
    Ty ty
    int len

ctypedef struct MLErr:
    char *line
    long line_n

ctypedef struct MLOk:
    char **lines
    long nlines

cdef union MLResult:
    MLOk ok
    MLErr err

ctypedef struct MakeLinesResult:
    int err
    MLResult res    

cdef char* copy_string(char* src, long len):
    cdef char *str = <char *> malloc(len + 1)
    str[len] = 0
    strncpy(str, src, len)
    return str

cdef MakeLinesResult make_bad_line_err(char *line, long len, int line_n):
    cdef MLErr err
    err.line_n = line_n
    err.line = copy_string(line, len)
    
    cdef MakeLinesResult res
    res.err = BAD_LINE
    res.res.err = err
    
    return res

cdef MakeLinesResult make_ok(char **lines, long nlines):
    cdef MLOk ok
    ok.lines = lines
    ok.nlines = nlines
    
    cdef MakeLinesResult res
    res.res.ok = ok
    res.err = 0

    return res

cdef MakeLinesResult make_err(int error):
    cdef MLErr err
    err.line_n = -1
    err.line = NULL
    
    cdef MakeLinesResult res
    res.res.err = err
    res.err = error
    
    return res

cdef char CR = 0x0D # '\r'
cdef char LF = 0x0A # '\n'
cdef MakeLinesResult make_lines(Field *fields, int nfields, char *data, long data_len):
    cdef MakeLinesResult res
    cdef MLErr err
    cdef MLOk ok

    cdef long expected_line_len = 0
    cdef int i = 0

    while i < nfields:
        expected_line_len += fields[i].len
        i += 1

    if expected_line_len <= 0:
        return make_err(BAD_FIELDS)

    cdef long line_n = 0
    cdef long len
    cdef char **lines = <char **> malloc(sizeof(char *) * (data_len / expected_line_len))
    cdef char *str = data
    cdef char c = 0
    cdef char *current_line_head = str

    if lines == NULL:
        return make_err(OUT_OF_MEMORY)
    while True:
        c = str[0]
        
        if c == CR or c == LF:
            len = <long> (str - current_line_head)
            
            if len != expected_line_len:
                free(lines)
                return make_bad_line_err(current_line_head, len, line_n)
            
            str += 1
            
            while True:
                c = str[0]
                if c == CR or c == LF:
                    str += 1
                    continue
                elif c == 0:
                    lines[line_n] = current_line_head
                    line_n += 1         
                    return make_ok(lines, line_n)
                else:
                    lines[line_n] = current_line_head
                    current_line_head = str
                    line_n += 1
                    break
            
            continue

        elif c == 0:
            len = <long> (str - current_line_head)
            if len != expected_line_len:
                free(lines)
                return make_bad_line_err(current_line_head, len, line_n)
            
            lines[line_n] = current_line_head
            line_n += 1

            return make_ok(lines, line_n)
        else:
            str += 1 

    # Unreachable

ctypedef struct ParsedResult:
    long line_n
    long field_index

cdef ParsedResult _parse(char **lines, long nlines, Field *fields, void **output, long nfields):
    cdef ParsedResult pr
    cdef long i = 0
    cdef int j, ty = 0, length = 0
    cdef char *line
    cdef char temp
    cdef int res

    while i < nlines:
        line = lines[i]
        j = 0

        while j < nfields:
            length = fields[j].len
            temp = line[length]
            line[length] = 0
            ty = fields[j].ty
            
            if ty == Float64:
                res = parse_f64(output[j], line, i, j)
            elif ty == Int64:
                res = parse_i64(output[j], line, i, j)
            elif ty == String:
                res = parse_string(output[j], line, i, j)
            if res != 0:
                pr.line_n = i
                pr.field_index = j
                return pr
            
            line[length] = temp
            line += length
            j += 1
        
        i += 1

    pr.line_n = -1
    pr.field_index = -1
    return pr

ctypedef struct NextLineResult:
    char *line
    int err

cdef NextLineResult fast_next_line(char* current_position, char* end_position, int line_len):
    cdef char *new_pos = current_position + line_len
    cdef NextLineResult r

    if new_pos >= end_position:
        r.line = NULL
        r.err = 0
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

cdef FastParseResult _fast_parse(char *data, long data_len, long max_nlines, int line_len, Field *fields, void **output, int nfields):
    cdef long line_n = 0
    cdef char *end = data + data_len
    cdef char *t = NULL
    cdef int length = 0, j = 0
    cdef char temp = 0
    cdef int res = 0
    cdef FastParseResult pr
    cdef NextLineResult nlr
    nlr.line = data

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

    cdef long fsize = ftell(f)
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
    if fread(str, 1, fsize, f) != fsize:
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

cdef (Field *, int) make_fields(list fields):
    """
    Turns a python list of field tuples into a c array of fields.

    :return: 
        (NULL, 0) if out of memory
        (NULL, -1) if there was an issue with the provided field tuples
        (<ptr>, 0) on success
    """

    cdef int nfields
    cdef Field *cfields = NULL
    cdef int i = 0
    try:
        nfields = len(fields)
        cfields = <Field *> malloc(sizeof(Field) * nfields)
        
        # Check if allocation failed
        if cfields == NULL:
            return NULL, 0
        for (ty, length) in fields:
            if type(length) != int:
                raise Exception("Expected type int for length, instead got {}".format(type(length)))
            if type(ty) != Ty:
                if type(ty) == int:
                    if ty > MAX_T or ty < 0:
                        raise Exception("Invalid ty id {}".format(ty))
                else:
                    raise Exception("Expected int or Ty for ty field, instead got {}".format(type(ty)))

            cfields[i].ty = ty
            cfields[i].len = length
            i += 1
        return cfields, nfields
    except Exception as e:
        print(f"Got exception {e}")
        if cfields != NULL:
            free(cfields)
            cfields = NULL
        return cfields, -1

"""
def t(list pyfields, bytes filename):
    cdef ReadWholeFileResult file_res = read_whole_file(filename)
    if file_res.err != 0:
        return f"Failed to read whole file, encountered error {file_res.err}"

    cdef char *data = file_res.data
    cdef long data_len = file_res.data_len

    cdef (Field *, int) fields_res = make_fields(pyfields)
    cdef Field *fields = fields_res[0]
    cdef int nfields = fields_res[1]
    if fields == NULL:
        free(fields)
        return "Failed to parse fields"
    if nfields == 0:
        free(fields)
        return "Cannot have zero fields"

    cdef int linelen = 0
    for i in range(nfields):
        linelen += fields[i].len
    # cdef MakeLinesResult make_lines(Field *fields, int nfields, char *data, long data_len):
    cdef MakeLinesResult lines_result = make_lines(fields, nfields, data, data_len)

    cdef char** lines, temp
    if lines_result.err != 0:
        return f"Got error {lines_result.err} on line {lines_result.res.err.line_n + 1}"
    
    cdef long nlines = lines_result.res.ok.nlines

    lines = lines_result.res.ok.lines
    cdef AllocationResult output_obj = allocate_field_outputs(fields, nfields, nlines)
    if output_obj is None:
        return "Failed to allocate output"
    cdef void **ptrs = output_obj.ptrs
    cdef ParsedResult pr = _parse(lines, nlines, fields, output_obj.ptrs, nfields) 
    if pr.line_n != -1:
        return "Failed to parse"
    cdef list py_handles = output_obj.py_handles

    free(lines)
    free(fields)
    free(data)
    return "Ok!"
"""

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

class FieldException(Exception):
    
    def __init__(self, err):
        self.err = err

    def __str__(self):
        return str(self.err)

def parse(list pyfields, filename):
    t = type(filename)
    if t not in (str, bytes):
        raise TypeError(f"Argument 'filename' has incorrect type (expected str or bytes, got {t}")
    cdef ReadWholeFileResult file_res = read_whole_file(bytes(filename))
    cdef char *error = NULL
    if file_res.err != 0:
        error = strerror(file_res.err)
        raise OSError(file_res.err, str(error))

    cdef char *data = file_res.data
    cdef long data_len = file_res.data_len

    cdef (Field *, int) fields_res = make_fields(pyfields)
    cdef Field *fields = fields_res[0]
    cdef int nfields = fields_res[1]

    if fields == NULL:
        free(data)
        raise FieldException("Supplied fields were not in the proper format.")
    
    if nfields == 0:
        free(fields)
        free(data)
        raise FieldException("Cannot have zero fields.")

    cdef int linelen = 0
    for i in range(nfields):
        linelen += fields[i].len

    if linelen == 0:
        free(fields)
        free(data)
        raise FieldException("Cannot have zero width fields.")
    
    cdef long max_lines = data_len / linelen

    cdef AllocationResult output_obj = allocate_field_outputs(fields, nfields, max_lines)
    if output_obj is None:
        return "Failed to allocate output"
    cdef void **ptrs = output_obj.ptrs
    cdef FastParseResult pr = \
            _fast_parse(data, data_len, max_lines, linelen, fields, output_obj.ptrs, nfields) 
        
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
    
cdef AllocationResult allocate_field_outputs(const Field *fields, int nfields, long nlines):
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
