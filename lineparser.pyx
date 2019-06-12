from libc.stdlib cimport malloc, free, atoi, atof
from libc.stdio cimport fseek, fopen, fclose, ferror, ftell, fread, SEEK_END, SEEK_SET, FILE, printf
from libc.string cimport strncpy
from libc.errno cimport errno
import numpy as np
from libc.stdint cimport int32_t, int64_t

cdef int OUT_OF_MEMORY = 1
cdef int BAD_FIELDS = 2
cdef int BAD_LINE = 3
cdef int IO_ERROR = 4

cdef int parse_f64(void *output, const char *str, long line_n, int field_len):
    global errno
    cdef double *doutput = <double *> output
    cdef int prev = errno
    errno = 0
    doutput[line_n] = atof(str);
    if errno != 0:
        errno = prev
        return 1
    errno = prev
    return 0

cdef int parse_i64(void *output, const char *str, long line_n, int field_len):
    global errno
    cdef int64_t *ioutput = <int64_t *> output
    cdef int prev = errno
    errno = 0
    ioutput[line_n] = atoi(str)
    if errno != 0:
        errno = prev
        return 1
    errno = prev
    return 0

cdef int parse_string(void *output, const char *str, long line_n, int field_len):
    cdef list loutput = <list> output
    cdef bytes copy = <bytes> str
    loutput.append(copy)
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
        print(f"c = {c}")
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
    char *line

cdef ParsedResult parse(char **lines, long nlines, Field *fields, void **output, long nfields):
    pass

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
    print("Parsed fields ok.")

    cdef int linelen = 0
    for i in range(nfields):
        linelen += fields[i].len
    
    # cdef MakeLinesResult make_lines(Field *fields, int nfields, char *data, long data_len):
    cdef MakeLinesResult lines_result = make_lines(fields, nfields, data, data_len)
    cdef char** lines, temp
    free(fields)
    if lines_result.err == 0:
        print("Made lines ok")
        lines = lines_result.res.ok.lines
        for i in range(0, lines_result.res.ok.nlines):
            temp = lines[i][linelen] 
            lines[i][linelen] = 0;
            print(f"<{lines[i]}>")
            lines[i][linelen] = temp
        free(lines)
        free(data)
        return "Ok!"
    else:
        return f"Got error {lines_result.err} on line {lines_result.res.err.line_n + 1}"

cdef class AllocationResult:

    cdef void **ptrs
    cdef object py_handles
    
cdef object allocate_field_outputs(Field *fields, int nfields, long nlines):
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
    cdef Field field
    cdef double[:] dptr
    cdef int64_t[:] lptr
    cdef int32_t[:] iptr

    while i < nfields:
        field = fields[i]
        if field.ty == Float64:
            arr = np.zeros(nlines, dtype=np.float64)
            py_handles.append(arr)
            dptr = arr
            ptrs[i] = <void *> &dptr[0]
        elif field.ty == Int64:
            arr = np.zeros(nlines, dtype=np.int64)
            py_handles.append(arr)
            lptr = arr
            ptrs[i] = <void *> &lptr[0]
        elif field.ty == String:
            arr = []
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
