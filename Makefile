NUMPY_INCLUDES=-I/usr/lib/python3.7/site-packages/numpy/core/include

all:
	make clean
	make build
clean:
	rm -rf lineparser

build: clean
	gcc $$(python-config --includes) $(NUMPY_INCLUDES) -o lineparser lineparser.c
