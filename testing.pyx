from libc.stdlib cimport malloc, free
from cpython cimport array
import array

# output, str, line_n, strlen
ctypedef int (*ParseFn)(void *, const char *, long, int)

cdef int parse_f64(void *output, const char *str, long line_n, int field_len):
    pass

cdef int parse_i64(void *output, const char *str, long line_n, int field_len):
    pass

cdef int parse_string(void *output, const char *str, long line_n, int field_len):
    pass

cpdef enum Ty:
    Float64 = 0
    Int64 = 1
    String = 2

cdef ParseFn *parse_fn_map = [parse_f64, parse_i64, parse_string]

MAX_T = 2

ctypedef struct Field:
    Ty ty
    int len
    ParseFn parse_fn


cdef (Field *, int) make_fields(list fields):
    """
    Turns a python list of field tuples into a c array of fields.

    :return: 
        (NULL, 0) if out of memory
        (NULL, 1) if there was an issue with the provided field tuples
        (<ptr>, 0) on success
    """

    cdef int nfields
    cdef Field *cfields = NULL
    cdef Field temp_field
    try:
        nfields = len(fields)
        cfields = <Field *> malloc(sizeof(Field) * nfields)
        
        # Check if allocation failed
        if cfields == NULL:
            return cfields, 0

        for (ty, length) in fields:
            if type(length) != int:
                raise Exception("Expected type int for length, instead got {}".format(type(length)))
            if type(ty) != Ty:
                if type(ty) == int:
                    if ty > MAX_T or ty < 0:
                        raise Exception("Invalid ty id {}".format(ty))
                else:
                    raise Exception("Expected int or Ty for ty field, instead got {}".format(type(ty)))

            temp_field.ty = ty
            temp_field.len = length
            temp_field.parse_fn = parse_fn_map[<int> temp_field.ty]

        return cfields, 0
    except:
        if cfields != NULL:
            free(cfields)
            cfields = NULL
        return cfields, 1

cdef void* list_as_ptr(object o):
    return <void *> o

cdef (list, void **) allocate_field_outputs(Field *fields, int nfields, long nlines):
    """
    Allocates output based on the field specifications. The only data type that doesn't get an
    an array for output is string, since c strings don't mix with python very well; so to minimize
    copies a python list will be hold the python strings.

    :return: NULL if any of the fields have an invalid type, otherwise returns a pointer which is a
    list of pointers to field output containers
    """
    cdef list py_handles = []
    cdef void **ptrs = <void**> malloc(sizeof(void*) * len(specs))
    cdef array.array arr = array.array('i', 0)
    cdef int i = 0
    cdef Field field

    while i < nfields:
        field = fields[i]
        if field.ty == Int64:
            arr = array.array('')
        elif field.ty == Float64:
        elif field.ty == String:
        else:
            free(ptrs)
            return NULL
        i += 1
