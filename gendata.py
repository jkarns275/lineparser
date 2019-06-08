import random
import string

def random_string(length):
    return "".join(random.choice(string.ascii_lowercase) for i in range(length))

with open('testdata.par', "w+") as f:
    for i in range(0, 1000000):
        # 3 space e float takes between 0 and one takes up 6 + n decimals spaces
        f.write("{:6d}{:7s}{:10d}{:.3e}{:7s}\n".format( \
                random.randrange(0,999999), random_string(7), random.randrange(0, 9999999999),
                random.random(), random_string(7)))

