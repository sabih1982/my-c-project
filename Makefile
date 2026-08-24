CC=gcc
CFLAGS=-Wall -Wextra -std=c11
TARGET=calculator
SOURCES=main.c calculator.c

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCES)

clean:
	rm -f $(TARGET) tests/test_runner

test: $(TARGET)
	@echo "🔨 Compiling tests..."
	$(CC) $(CFLAGS) -o tests/test_runner tests/test_calculator.c calculator.c
	@echo "🧪 Running tests..."
	@./tests/test_runner || (echo "❌ Tests failed!" && exit 1)
	@echo "✅ All tests passed!"

.PHONY: all clean test
