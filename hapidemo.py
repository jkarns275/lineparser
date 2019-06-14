from hapi import *
import time

start = time.time()
db_begin('data')
end = time.time()
print(f"Took {end - start} seconds")
