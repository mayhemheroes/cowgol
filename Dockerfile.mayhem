FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y g++ software-properties-common make

RUN add-apt-repository ppa:vriviere/ppa
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y ninja-build lua5.1 pasmo libz80ex-dev flex libbsd-dev libreadline-dev bison binutils-arm-linux-gnueabihf binutils-i686-linux-gnu binutils-powerpc-linux-gnu binutils-m68k-linux-gnu binutils-m68k-atari-mint qemu-user gpp 64tass nasm

ADD . /repo
WORKDIR /repo
RUN make -j8

RUN mkdir -p /deps
RUN ldd /repo/bin/cowfe-80386.nncgen.exe | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /repo/bin/cowfe-80386.nncgen.exe /repo/bin/cowfe-80386.nncgen.exe
ENV LD_LIBRARY_PATH=/deps
