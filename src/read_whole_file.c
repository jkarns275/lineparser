#include <stdlib.h>

typedef struct {
    __int64 data_len;
    char *data;
    int err;
    int io_err;
} ReadWholeFileResult;

#define OUT_OF_MEMORY 1
#define BAD_FIELDS 2
#define BAD_LINE 3
#define IO_ERROR 4
#define PREMATURE_EOF 5
#define PARSE_ERROR 6
#define FILE_NOT_FOUND 7

ReadWholeFileResult make_io_error(int io_err) {
    ReadWholeFileResult r =
        { .data_len = 0, .data = NULL, .err = IO_ERROR, .io_err = io_err };
    return r;
}

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32) && !defined(__CYGWIN__)

#include <windows.h>
#include <tchar.h>
#include <strsafe.h>

ReadWholeFileResult read_whole_file_(const char *path) {
    ReadWholeFileResult r;
    // open file
    HANDLE file = CreateFile(
        path,
        GENERIC_READ,
        FILE_SHARE_READ,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL);
    
    if (file == INVALID_HANDLE_VALUE) {
        r.err = FILE_NOT_FOUND;
        r.io_err = 0;
        r.data_len = 0;
        r.data = NULL;
        return r;
    }

    // get size
    LARGE_INTEGER file_size_li;

    if (GetFileSizeEx(file, &file_size_li) == 0) {
        // Handle error.
        CloseHandle(file);
        return make_io_error(0);
    }

    __int64 file_size = file_size_li.QuadPart;
    __int64 bytes_left = file_size;

    if (sizeof(size_t) == 4 && file_size > 0x7FFFFFFF) {
        // Cant read file over 2 GB on a 32 bit system :(
        CloseHandle(file);
        r.err = OUT_OF_MEMORY;
        r.io_err = 0;
        r.data_len = 0;
        r.data = NULL;
        return r;
    }

    char *data = (char *) malloc(file_size + 1);
    
    DWORD bytes_read = 0;
    __int64 bytes_read_total = 0;
    while (bytes_left != 0) {

        // 0x7FFFFFFF is the largest positive number a 32 bit integer can represent
        DWORD bytes_to_read = (DWORD) min(0x7FFFFFFF, bytes_left);

        void *data_ptr = data +  bytes_read_total;

        if (ReadFile(file, data_ptr, bytes_to_read, &bytes_read, NULL) == 0) {
            // handle error and return
            free(data);
            CloseHandle(file);
            return make_io_error(0);
        }

        bytes_read_total += (__int64) bytes_read;
        bytes_left -= (__int64) bytes_read;
    }

    data[bytes_read_total] = 0;

    ReadWholeFileResult a = { .data = data, .data_len = file_size, .err = 0, .io_err = 0 };
    return a;
}

#else
#include <errno.h>
#include <stdio.h>

ReadWholeFileResult read_whole_file_(char *path) {
    int prev = errno;
    ReadWholeFileResult r;

    FILE *f = fopen(path, "rb");

    // file couldnt be opened
    if (f == NULL) {
        r = make_io_err(errno);
        errno = prev;
        return r;
    }

    errno = prev;

    if fseek(f, 0, SEEK_END) != 0 {
        r = make_io_err(ferror(f));
        fclose(f);
        return r;
    }

    long fsize = (long) ftell(f);
    if fseek(f, 0, SEEK_SET) != 0 {
        r = make_io_err(ferror(f));
        fclose(f);
        return r;
    }

    char *data = (char *) malloc(fsize + 1);
    if (data == NULL) {
        fclose(f);
        r.data = NULL;
        r.data_len = 0;
        r.err = OUT_OF_MEMORY;
        return r;
    }

    // Either premature EOF or error; almost certainly NOT EOF though since we just checked
    // the length of the file
    if ((long) fread(data, 1, fsize, f) != fsize) {
        free(data);
        r = make_io_err(ferror(f));
        fclose(f);
        return r;
    }

    // Null terminate
    data[fsize] = 0;

    fclose(f);
    r.data = data;
    r.data_len = fsize;
    r.err = 0;
    return r;
}
#endif