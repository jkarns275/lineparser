from lineparser import named_parse, NamedField
import time

def read_strong_line_file(data_file):
    start = time.time()
    print("\n . . . . . reading data from "+data_file)
    input_int_format = [ NamedField('nu', float, 12),         NamedField('sw', float,10),  NamedField('e_low', float, 12),
                         NamedField('J_up', str, 6),         NamedField('J_lo', str, 6), NamedField('var_shift', str, 14),
                         NamedField('hi_j_shift', str, 14), NamedField('T_int', str, 6) ]
    read_lines = named_parse( input_int_format, data_file )
    band_n = len(read_lines['nu'])
    end = time.time()
    print( '           >> Number of lines : '+str(band_n))
    print(f'           >> Parsed in {end - start} seconds')
    return read_lines, band_n

all_strong_lines, all_strong_lines_n = read_strong_line_file('data/big_data')
