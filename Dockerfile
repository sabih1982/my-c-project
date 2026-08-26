FROM ubuntu:22.04

EXPOSE 8080
EXPOSE 2121

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LD_LIBRARY_PATH="/opt/utbot_distr/install/lib:/opt/utbot_distr/debs-install/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
ENV PATH="/opt/utbot_distr/server-install:/opt/utbot_distr:${PATH}"
ENV UTBOT_HOME="/opt/utbot_distr"

# Create utbot user
RUN groupadd -r utbot && \
    useradd -r -g utbot -m -s /bin/bash utbot && \
    echo "utbot:utbot" | chpasswd

# Install dependencies including bear and cmake
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    git \
    wget \
    unzip \
    libgtest-dev \
    libz3-dev \
    python3 \
    python3-pip \
    lsb-release \
    curl \
    sudo \
    bear \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install compiledb for compile_commands.json generation
RUN pip3 install compiledb

# Give utbot user sudo privileges
RUN echo "utbot ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Download and extract UTBot
WORKDIR /opt
RUN wget https://github.com/UnitTestBot/UTBotCpp/releases/download/2024.3.0/utbot-release-2024.3.0.zip \
    && unzip utbot-release-2024.3.0.zip \
    && rm utbot-release-2024.3.0.zip \
    && tar -xf utbot_distr.tar.gz \
    && rm utbot_distr.tar.gz \
    && chown -R utbot:utbot utbot_distr \
    && cd utbot_distr \
    && chmod -R 755 . \
    && mkdir -p logs \
    && touch logs/latest.log \
    && chown -R utbot:utbot logs \
    && chmod -R 755 logs

# Create wrapper script
RUN echo '#!/bin/bash\n\
export LD_LIBRARY_PATH=/opt/utbot_distr/install/lib:/opt/utbot_distr/debs-install/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH\n\
exec /opt/utbot_distr/server-install/utbot "$@"\n\
' > /usr/local/bin/utbot && chmod +x /usr/local/bin/utbot

USER utbot

# Set up environment
RUN echo 'export LD_LIBRARY_PATH=/opt/utbot_distr/install/lib:/opt/utbot_distr/debs-install/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH' >> /home/utbot/.bashrc && \
    echo 'export PATH=/opt/utbot_distr/server-install:/opt/utbot_distr:$PATH' >> /home/utbot/.bashrc && \
    echo 'export UTBOT_HOME=/opt/utbot_distr' >> /home/utbot/.bashrc

# Start UTBot server
RUN cd /opt/utbot_distr && ./utbot_server_restart.sh

WORKDIR /app
COPY --chown=utbot:utbot . .

# Generate compile_commands.json
RUN mkdir -p build && \
    cd build && \
    cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON .. || \
    (cd /app && bear -- make) || \
    (cd /app && compiledb make)

# Create tests directory
RUN mkdir -p tests && chmod 755 tests

# Build the project
RUN make clean && make

# Run tests
RUN make test

# Generate UTBot tests using the project command
RUN utbot generate --project-path "/app/" project || \
    utbot generate --project-path "/app/build" project || \
    echo "UTBot project generation skipped"

CMD ["/bin/bash", "-c", "cd /opt/utbot_distr && ./utbot_server_restart.sh && tail -f /dev/null"]