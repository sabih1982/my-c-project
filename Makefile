CC=gcc
CFLAGS=-Wall -Wextra -std=c11
TARGET=calculator
SOURCES=main.c calculator.c

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCES)

clean:
	rm -f $(TARGET)

test: $(TARGET)
	./tests/run_tests