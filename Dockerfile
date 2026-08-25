#Docker command to build the image
# docker build -t my-c-app .
FROM gcc:latest

RUN apt-get update && apt-get install -y \
    wget unzip make libgtest-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN wget https://github.com/UnitTestBot/UTBotCpp/releases/download/2024.3.0/utbot-release-2024.3.0.zip \
    && unzip utbot-release-2024.3.0.zip \
    && rm *.zip \
    && chmod +x unpack_and_run_utbot.sh \
    && ./unpack_and_run_utbot.sh --install

WORKDIR /app
COPY . .
RUN make clean && make && make test

CMD ["/bin/bash"]