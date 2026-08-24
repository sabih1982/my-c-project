FROM gcc:latest

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    make \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . .

# Build the project
RUN make clean && make

# Run tests
RUN make test

# Default command
CMD ["./calculator"]
