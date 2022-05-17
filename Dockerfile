FROM --platform=linux/amd64 ubuntu:20.04

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y g++ software-properties-common make

RUN add-apt-repository ppa:vriviere/ppa
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y ninja-build lua5.1 pasmo libz80ex-dev flex libbsd-dev libreadline-dev bison binutils-arm-linux-gnueabihf binutils-i686-linux-gnu binutils-powerpc-linux-gnu binutils-m68k-linux-gnu binutils-m68k-atari-mint qemu-user gpp 64tass nasm

ADD . /repo
WORKDIR /repo
RUN make -j8
