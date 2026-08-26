CC=gcc
CXX=g++
CFLAGS=-Wall -Wextra -std=c11
CXXFLAGS=-std=c++11
TARGET=calculator
SOURCES=main.c calculator.c
UTBOT_DIR=tests/utbot
UTBOT_RUNNER=$(UTBOT_DIR)/utbot_runner

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCES)

clean:
	rm -f $(TARGET) tests/test_runner $(UTBOT_RUNNER)
	rm -rf $(UTBOT_DIR)

# Generate UTBot tests
generate-utbot-tests:
	@echo "📝 Auto-generating UTBot tests..."
	@mkdir -p $(UTBOT_DIR)
	@utbot --generate-tests \
		--source-file calculator.c \
		--output-dir $(UTBOT_DIR) \
		--framework googletest \
		--functions all 2>/dev/null || \
		echo "⚠️  UTBot generation failed. Make sure UTBot is installed."

# Run manual tests
test: $(TARGET)
	@echo "🔨 Compiling manual tests..."
	@mkdir -p tests
	$(CC) $(CFLAGS) -o tests/test_runner tests/test_calculator.c calculator.c
	@echo "🧪 Running manual tests..."
	@./tests/test_runner || (echo "❌ Manual tests failed!" && exit 1)
	@echo "✅ All manual tests passed!"

# Add to your Makefile
compile-commands:
	@echo "📝 Generating compile_commands.json..."
	@bear -- make || compiledb make || (mkdir -p build && cd build && cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..)

# Updated UTBot generation
generate-utbot-tests: compile-commands
	@echo "📝 Generating UTBot tests..."
	@mkdir -p $(UTBOT_DIR)
	@utbot generate --project-path "/app/" project || \
	 utbot generate --project-path "/app/build" project || \
	 echo "⚠️  UTBot generation failed"

# Run all tests
all-tests: test utbot
	@echo "🎉 All tests completed!"

# Quick test (generate + run all)
quick: generate-utbot-tests all-tests

.PHONY: all clean test utbot all-tests generate generate-utbot-tests quick