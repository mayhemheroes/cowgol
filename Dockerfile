FROM --platform=linux/amd64 ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y     g++ make ninja-build lua5.1 pasmo libz80ex-dev flex libbsd-dev     libreadline-dev bison binutils-arm-linux-gnueabihf binutils-i686-linux-gnu     binutils-powerpc-linux-gnu binutils-m68k-linux-gnu qemu-user gpp 64tass nasm

ADD . /repo
WORKDIR /repo
RUN make -j8

RUN mkdir -p /deps
RUN ldd /repo/bin/cowfe-80386.nncgen.exe | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:22.04 AS package

COPY --from=builder /deps /deps
COPY --from=builder /repo/bin/cowfe-80386.nncgen.exe /repo/bin/cowfe-80386.nncgen.exe
ENV LD_LIBRARY_PATH=/deps
