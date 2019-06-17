import lineparser
import time

fields = [(lineparser.Float64, 12), (lineparser.Float64, 10), (lineparser.Float64, 12), 
        (lineparser.String, 6), (lineparser.String, 6), (lineparser.String, 14),
        (lineparser.String, 14), (lineparser.Float64, 6)]

start = time.time()
result = lineparser.parse(fields, b'data/big_data.par')
end = time.time()
print(f"Took {end - start} seconds")

for i in range(len(fields)):
    print(len(result[i]))
