/*
  #include <Python.h>

typedef enum {
     Int,
     Float,
     String
} Ty;



static PyObject* howdy(PyObject* self, PyObject* args) {
    printf("Howdy\n");
    Py_RETURN_NONE;
}

static PyMethodDef methods[] = {
    {"howdy", howdy, METH_NOARGS, "Prints Howdy" },
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef myModule = {
    PyModuleDef_HEAD_INIT,
    "myModule",
    "Test Module",
    -1,
    methods
};

PyMODINIT_FUNC PyInit_myModule(void) {
    return PyModule_Create(&myModule);
    }*/

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define ZERO_LENGTH_LINE 1
#define BAD_LINE 2

typedef enum _Ty {
    Int,
    Float,
    String
} Ty;

typedef struct _Field {
    Ty type;
    size_t len;
    int (*parse_fn) (void *, const char *, size_t, int);
} Field;

int parse_float(void *output, const char *str, size_t line_n, int _field_len) {
    double *foutput = (double *) output;
    int prev = errno;
    errno = 0;
    foutput[line_n] = atof(str);
    if (errno) {
            return -1;
    }
    errno = prev;
    return 0;
}

int parse_int(void *output, const char *str, size_t line_n, int _field_len) {
    int *ioutput = (int *) output;
    int prev = errno;
    errno = 0;
    ioutput[line_n] = atoi(str);
    if (errno) {
	errno = prev;
        return -1;
    }
    errno = prev;
    return 0;
}

int copy_string(void *output, const char *str, size_t line_n, int field_len) {
    char **soutput = (char **) output;
    soutput[line_n] = (char *) malloc(field_len);
    strcpy(soutput[line_n], str);
    return 0;
}

typedef struct _Result {
    int err;
    void *result;
} Result;

typedef struct { int err; size_t nlines; char **lines; }  MakeLinesResult;

MakeLinesResult make_lines(Field *fields, size_t nfields, const char const *str, size_t data_len) {
    size_t expected_line_len = 0;
    for (int i = 0; i < nfields; i += 1)
        expected_line_len += fields[i].len;

    if (expected_line_len == 0) {
        MakeLinesResult r = { .err = ZERO_LENGTH_LINE, .lines = NULL };
        return r;
    }
    size_t line_n = 0;
    size_t len;
    const char **lines = (const char **) malloc(sizeof(char*) * (data_len / expected_line_len));
    
    const char *current_line_head = str;
    int j = 0;
    while (*str) {

        start:;

        switch (*str) {
        case '\n':
        case '\r':
            len = (size_t) (str - current_line_head);
	    if (len == 0) {
	        // Now find the end of sequential newlines, or end of string
                for (;;) {
                    switch (*str) {
                    case '\r':
                    case '\n':
                        str += 1;
                        continue;
                        
                    case '\0':
                        lines[line_n] = NULL; // Null terminate the list
                        goto done;

                    default:
                        current_line_head = str;
                        goto start;
                    }
                }    
	    }

	    if (len != expected_line_len) {
                free(lines);
                MakeLinesResult r = { .err = BAD_LINE, .lines = NULL };
                return r;
            }


            // Now find the end of sequential newlines, or end of string
            for (;;) {
                switch (*str) {
                case '\r':
                case '\n':
                    str += 1;
                    continue;
                    
                case '\0':
                    lines[line_n] = current_line_head;
                    line_n += 1;
                    lines[line_n] = NULL; // Null terminate the list
                    goto done;

                default:
                    lines[line_n] = current_line_head;
                    line_n += 1;
                    current_line_head = str;
		    goto start;
                }
            }
            break; // Not necessary (i think?)
        
        default:
            str += 1;
        }
    }

    done:;
    
    MakeLinesResult r = { .err = 0, .lines = lines, .nlines = line_n };
    return r;
}

typedef struct _ParsedResult {
    size_t line_n, field_index;
} ParsedResult;

/**
 *
 * Returns { -1, _ } on success. Otherwise { line_n, field_index } (which points to the
 * location of the error) is returned. 
 *
 **/
ParsedResult parse(char **lines, size_t nlines, Field *fields, void **output, size_t nfields) {
    char *line, temp;
    size_t len;

    for (size_t line_n = 0; line_n < nlines; line_n += 1) {
        line = lines[line_n];
        for (size_t i = 0; i < nfields; i += 1) {
	    len = fields[i].len;
	    temp = line[len];
            line[len] = 0;
	    if ((fields[i].parse_fn)(output[i], line, line_n, len)) {
                ParsedResult r = { line_n, i };
		return r;
            }

            line[len] = temp;
            line += len;
        }
    }
    ParsedResult r = { -1, -1 };
    return r;
}

void **make_output(Field *fields, size_t nfields, size_t nlines) {
    void **ptrs = (void **) malloc(sizeof(void *) * nfields);
    for (int i = 0; i < nfields; i += 1) {
            switch (fields[i].type) {
        case Int:
            ptrs[i] = (int *) malloc(sizeof(int) * nlines);
            break;
        
        case Float:
            ptrs[i] = (double *) malloc(sizeof(double) * nlines);        
            break;
         
        case String:
            ptrs[i] = (char **) malloc(sizeof(char *) * nlines);
            break;

        default: 
                break;
        }
    }
    return ptrs;
}

void **print_output(void **ptrs, Field *fields, size_t nfields, size_t nlines) {
    
    int *iptr;
    char **sptr;
    double *dptr;
    for (int j = 0; j < nlines; j += 1) {
        for (int i = 0; i < nfields; i += 1) {
            if (i != 0) printf(", ");
	    switch (fields[i].type) {
            case Int:
                iptr = (int *) ptrs[i];
                printf("%d", iptr[j]);    
                break;
            
            case Float:
                dptr = (double *) ptrs[i];
                printf("%f", dptr[j]);                   
		break;
             
            case String:
		sptr = (char **) ptrs[i];
                printf("\"%s\"", sptr[j]);
		break;

            default: 
                    break;
            
	    }
        }
	printf("\n");
    }
} 

int main(int argn, char **argv) {
    if (argn < 2) return 1;

    FILE *f = fopen(argv[1], "rb");
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *str = malloc(fsize + 1);
    fread(str, 1, fsize, f);
    fclose(f);

    char *s = str;
   
    str[fsize] = 0;
    
    size_t nfields = 5;
    Field fields[] = {  { .type = Int, .len = 6, .parse_fn = parse_int },
                        { .type = String, .len = 7, .parse_fn = copy_string },
                        { .type = Int, .len = 10, .parse_fn = parse_int },
                        { .type = Float, .len = 9, .parse_fn = parse_float },
                        { .type = String, .len = 7, .parse_fn = copy_string}, };
    char** strs;
    MakeLinesResult res = make_lines(fields, 5, str, fsize);
    
    if (res.lines == NULL) {
        printf("There was an error (error %d).\n", res.err);
        free(str);
        return -1;
    }

    int i = 0;
    char** lines = (char**) res.lines;

    void **output = make_output(fields, nfields, res.nlines);
    ParsedResult pr = parse(lines, res.nlines, fields, output, nfields);
    if (pr.line_n != -1) printf("Failed to parse properly\n");
// int[2] parse(const char const **lines, size_t nlines, Field *fields, void **output, size_t nfields) {

    printf("Parsed OK\n");

    free(lines);
    free(output);
    free(str);

    return 0;
}
