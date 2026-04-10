FROM --platform=linux/amd64 ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y     g++ make python3 pkg-config moreutils ninja-build lua5.1 pasmo libz80ex-dev flex libbsd-dev     libreadline-dev bison binutils-arm-linux-gnueabihf binutils-i686-linux-gnu     binutils-powerpc-linux-gnu binutils-m68k-linux-gnu qemu-user gpp 64tass nasm

ADD . /repo
WORKDIR /repo
RUN make -j8

RUN mkdir -p /deps
RUN ldd /repo/bin/cowfe-for-80386-with-nncgen | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:22.04 AS package

COPY --from=builder /deps /deps
COPY --from=builder /repo/bin/cowfe-for-80386-with-nncgen /repo/bin/cowfe-for-80386-with-nncgen
ENV LD_LIBRARY_PATH=/deps
