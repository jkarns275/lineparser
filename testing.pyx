from libc.stdlib cimport malloc, free
from cpython cimport array
import array

cdef void* list_as_ptr(object o):
    return <void *> o

def allocate(specs, nlines):
    py_handles = []
    cdef void **ptrs = <void**> malloc(sizeof(void*) * len(specs))
    cdef array.array arr = array.array('i', 0)
    cdef int i = 0
    for spec in specs:
        if spec == "S":
            li = []
            py_handles.append(li)
            ptrs[i] = list_as_ptr(li)
        else:
            arr = array.array('d', nlines)
            py_handles.append(arr)
            ptrs[i] = arr.data.as_voidptr

        i += 1
