FROM gcc:latest

# Install additional dependencies including unzip and lsb-release
RUN apt-get update && apt-get install -y \
    cmake \
    git \
    wget \
    unzip \
    libgtest-dev \
    python3 \
    python3-pip \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Download and extract UTBot
WORKDIR /opt
RUN wget https://github.com/UnitTestBot/UTBotCpp/releases/download/2024.3.0/utbot-release-2024.3.0.zip \
    && unzip utbot-release-2024.3.0.zip \
    && rm utbot-release-2024.3.0.zip \
    # && tar -xzf utbot_distr.tar.gz \
    # && rm utbot_distr.tar.gz \
    # && cd utbot_distr \
    # && chmod +x unpack_and_run_utbot.sh \
    # && ./utbot_run_system.sh --install \
    && chmod +x unpack_and_run_utbot.sh \
    && ./unpack_and_run_utbot.sh --install \
    && ln -s /opt/utbot_distr/server-install/utbot /usr/local/bin/utbot

# Try to find where UTBot was installed
RUN find /opt -name "utbot" -type f 2>/dev/null || echo "UTBot not found in /opt"
RUN find /usr -name "utbot" -type f 2>/dev/null || echo "UTBot not found in /usr"
RUN find / -name "utbot" -type f 2>/dev/null | head -5 || echo "UTBot not found anywhere"

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
CMD ["/bin/bash"]