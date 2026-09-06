FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY src/headers ./headers
COPY src/source/calculator.c src/source/main.c ./source/

RUN gcc -Wall -Wextra -std=c11 -O2 \
    -I./headers \
    ./source/main.c ./source/calculator.c \
    -o /calculator

FROM ubuntu:22.04

COPY --from=build /calculator /usr/local/bin/calculator

ENTRYPOINT ["/usr/local/bin/calculator"]
