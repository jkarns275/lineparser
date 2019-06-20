from lineparser import NamedField, named_parse
import time

fields = [NamedField("a", float, 12), NamedField("b", float, 10), NamedField("c", float, 12), 
          NamedField("d", str, 6), NamedField("e", str, 6), NamedField("f", str, 14),
          NamedField("g", str, 14), NamedField("h", float, 6)]

start = time.time()
result = named_parse(fields, 'data/small_data.par')
end = time.time()
for k in result:
    print(f"{k} -> {result[k]}")
