#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

#define MAKE_PARSER(ty, parse_expr, output, str, line_n, field_len) \
    int prev = errno; \
    errno = 0; \
    ty *toutput = (ty *) output; \
    char *endptr = str; \
    char c; \
    toutput[line_n] = (ty) parse_expr; \
    if (errno) { \
        errno ^= prev; prev ^= errno; errno ^= prev; \
        return prev; \
    } \
    if (endptr - str < field_len) { \
        c = *endptr; \
        if (c != ' ' && c != '\n' && c != '\r') \
            return 1; \
    } \
    errno = prev; \
    return 0;

inline int parse_f64(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(double, strtod(str, &endptr), output, str, line_n, field_len)
}

inline int parse_f32(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(float, strtod(str, &endptr), output, str, line_n, field_len)
}

inline int parse_i64(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(int64_t, strtol(str, &endptr, 10), output, str, line_n, field_len)
}

inline int parse_i32(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(int32_t, strtol(str, &endptr, 10), output, str, line_n, field_len)
}

inline int parse_i16(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(int16_t, strtol(str, &endptr, 10), output, str, line_n, field_len)
}

inline int parse_i8(void *output, char *str, long line_n, int field_len) {
    MAKE_PARSER(int8_t, strtol(str, &endptr, 10), output, str, line_n, field_len)
}
