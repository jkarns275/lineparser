f = open("small_data.par")
s = f.read()
f.close()
for i in range(100000):
    print(s, end='')
