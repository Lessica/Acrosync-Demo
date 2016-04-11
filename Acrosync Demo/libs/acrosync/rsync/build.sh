#!/bin/bash

mkdir obj
BASE=$(cd `dirname $0`; pwd)
LIBS="../../acrosync-libs"
ARCH="x86_64"
CC="xcrun -sdk iphonesimulator clang -arch "
CFLAGS="-miphoneos-version-min=7.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iphonesimulator.sdk -fembed-bitcode -isystem $BASE/../../openssl-libs/x86_64/include -isystem $BASE/../../ssh-libs/x86_64/include"


$CC $ARCH $CFLAGS -c ./rsync_client.cpp -o obj/rsync_client.o
$CC $ARCH $CFLAGS -c ./rsync_entry.cpp -o obj/rsync_entry.o
$CC $ARCH $CFLAGS -c ./rsync_file.cpp -o obj/rsync_file.o
$CC $ARCH $CFLAGS -c ./rsync_io.cpp -o obj/rsync_io.o
$CC $ARCH $CFLAGS -c ./rsync_log.cpp -o obj/rsync_log.o
$CC $ARCH $CFLAGS -c ./rsync_pathutil.cpp -o obj/rsync_pathutil.o
$CC $ARCH $CFLAGS -c ./rsync_socketio.cpp -o obj/rsync_socketio.o
$CC $ARCH $CFLAGS -c ./rsync_socketutil.cpp -o obj/rsync_socketutil.o
$CC $ARCH $CFLAGS -c ./rsync_sshio.cpp -o obj/rsync_sshio.o
$CC $ARCH $CFLAGS -c ./rsync_stream.cpp -o obj/rsync_stream.o
$CC $ARCH $CFLAGS -c ./rsync_timeutil.cpp -o obj/rsync_timeutil.o
$CC $ARCH $CFLAGS -c ./rsync_util.cpp -o obj/rsync_util.o

mkdir -p "$LIBS/$ARCH"
ar cru "$LIBS/$ARCH/librsync.a" obj/*.o

