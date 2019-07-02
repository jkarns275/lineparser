import lineparser as lp
import numpy as np
import time

INTEGER_TYPES = (lp.Ty.Int64, lp.Ty.Int32, lp.Ty.Int16, lp.Ty.Int8)
FLOAT_TYPES = (lp.Ty.Float64, lp.Ty.Float32)

def run_n_tests(n, path, min_nfields, max_nfields, min_nlines, max_nlines):
    fg = FileGenerator()
    rng = np.random.RandomState(int(time.time()))
    for i in range(n):
        nfields = rng.randint(min_nfields, max_nfields + 1)
        nlines = rng.randint(min_nlines, max_nlines + 1)

        fields, values = fg.create_test_file(path, nfields, nlines)
        if not fg.parse_and_compare(path, fields, values):
            print(f"Test {i} failed")

class FileGenerator:

    def __init__(self):
        self.field_gen = FieldGenerator()
        self.field_spoofer = FieldSpoofer()

    def create_test_file(self, path: str, nfields: int, nlines: int):
        fields = list(map(lambda _: self.field_gen.next(), range(nfields)))
        values = []
        with open(path, "wb") as file:
            for i in range(nlines):
                file.write(self.make_line(fields, values))
        
        return fields, values

    def parse_and_compare(self, path: str, fields, exp_values):
        exp_nrows = len(exp_values)
        exp_ncols = len(fields)
       
        pr = lp.parse(fields, path)
        assert len(pr) == exp_ncols
        assert len(pr[0]) == exp_nrows

        for row in range(exp_nrows):
            for col in range(exp_ncols):
                if not pr[col][row] == exp_values[row][col]:
                    if fields[col].ty in FLOAT_TYPES and \
                        abs(pr[col][row] - exp_values[row][col]) < 0.001:
                        pass
                    else:
                        print(f"{pr[col][row]} != {exp_values[row][col]}; dtype={fields[col].ty}")
                        return False 
        return True

    def make_line(self, fields, line_values):
        spoofs = list(map(lambda f: self.field_spoofer.spoof(f), fields))
        spoofed_values = list(map(lambda i: spoofs[i][0], range(len(spoofs))))
        spoofed_strs = list(map(lambda i: spoofs[i][1], range(len(spoofs))))
        line_values.append(spoofed_values)
        return b"".join(spoofed_strs) + b"\n"

class FieldGenerator:

    tys = [lp.Ty.Float64, lp.Ty.Float32, lp.Ty.Int64, lp.Ty.Int32, lp.Ty.Int16, lp.Ty.Int8,
           lp.Ty.String, lp.Ty.Bytes]

    def __init__(self):
        self.rng = np.random.RandomState(int(time.time()))

    def next(self):
        index = self.rng.randint(len(FieldGenerator.tys))
        ty = FieldGenerator.tys[index]
        length = self.make_len(ty)
        return lp.Field(ty, length)

    def make_len(self, ty):
        if ty in FLOAT_TYPES:
            return self.rng.randint(10) + 7
        elif ty == lp.Ty.Int8:
            return self.rng.randint(2) + 1
        elif ty == lp.Ty.Int16:
            return self.rng.randint(4) + 1
        elif ty == lp.Ty.Int32:
            return self.rng.randint(7) + 1
        elif ty == lp.Ty.Int64:
            return self.rng.randint(10) + 1
        else:
            return self.rng.randint(15) + 5
class FieldSpoofer:
    """
    Creates strings that conform to the supplied field.
    """

    def __init__(self):
        self.rng = np.random.RandomState(int(time.time()))

    def spoof(self, field: lp.Field):
        if field.ty in FLOAT_TYPES:
            value, s = self.spoof_float(field.len)
        elif field.ty in INTEGER_TYPES:
            value, s = self.spoof_int(field.len)
        elif field.ty  == lp.Ty.String:
            value, s = self.spoof_string(field.len)
        elif field.ty == lp.Ty.Bytes:
            value, s = self.spoof_bytes(field.len)
        else:
            raise Exception("This should be unreachable")

        if len(s) < field.len:
            s = s + (" " * (field.len - len(s)))
        
        return value, bytes(s, 'utf-8')

    def spoof_float(self, length: int):
        if length < 7:
            raise Exception("Float fields must be at least 6 characters long")
        
        value = self.rng.randn()
        mantissa_len = length - 7
        fmt = f"%+.{mantissa_len}E"
        
        # Since there is going to be some accuracy loss from lobbing off decimals,
        # the value we supply here should be of that same lessened accuracy. To do
        # this we just format the value then parse it as a float.
        s = fmt % self.rng.randn()
        value = float(s)
        if len(s) > length:
            raise Exception("AAA")
        return value, s

    def spoof_int(self, len: int):
        max_n = (10 ** len) - 1
        min_n = -(10 ** (len - 1)) + 1

        value = self.rng.random_integers(min_n, max_n)
        s = str(value)
        return value, s

    def spoof_bytes(self, len: int):
        v = bytes(self.rng.randint(65, 126, len, dtype=np.int8))
        return v, v.decode('utf-8')

    def spoof_string(self, len: int):
        s = str(self.spoof_bytes(len)[0].decode('utf-8'))
        return s, s
