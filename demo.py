import lineparser
import time
fields = [(lineparser.Int64, 2), (lineparser.Int64, 1), (lineparser.Float64, 12), 
        (lineparser.Float64, 10), (lineparser.Float64, 10), (lineparser.Float64, 5),
        (lineparser.Float64, 5), (lineparser.Float64, 10),(lineparser.Float64, 4),
        (lineparser.Float64, 8), (lineparser.String, 15), (lineparser.String, 15),
        (lineparser.String, 15), (lineparser.String, 15), (lineparser.String, 6),
        (lineparser.String, 12), (lineparser.String, 1), (lineparser.Float64, 7), 
        (lineparser.Float64, 7)]
start = time.time()
print(lineparser.t2(fields, b'data/H2O.data'))
end = time.time()
print(f"Took {end - start} seconds")
