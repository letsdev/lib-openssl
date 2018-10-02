#!/bin/bash
set -e

VERSION=$1

if [ -z $VERSION ]; then
    echo "Missing VERSION as first parameter"
    exit 99
fi

. ./common.sh #source-only
download_openssl

## --------------------
## Parameters
## --------------------

ANDROID_SDK=21

## --------------------
## Variables
## --------------------

if [ ! -d "${ANDROID_NDK_HOME}" ]; then
  echo "ANDROID_NDK_HOME not defined or directory does not exist"
  exit 1
fi

## --------------------
## Functions
## --------------------

function clear_android_env {
	echo "Clear Android environment variables"
	unset CC
    unset CXX
    unset LINK
    unset LD
    unset AR
    unset AS
    unset RANLIB
    unset STRIP
    unset ARCH_FLAGS
    unset ARCH_LINK
    unset CPPFLAGS
    unset CXXFLAGS
    unset CFLAGS
    unset LDFLAGS
}

function build_android_arch {
    if [ -z $1 ]; then
        echo 'no ABI set'
        exit 1
        elif [ -z $2 ]; then
        echo 'no ARCH set'
        exit 1
        elif [ -z $3 ]; then
        echo 'no toolchain name set'
        exit 1
    fi
    local ABI=$1
    local ARCH=$2
    local TOOLCHAIN_NAME=$3
    local COMPILER=$4

    local SRC_DIR=${BUILD_DIR}/android-$ABI
    local LOG_FILE="$SRC_DIR/android-$ABI-$VERSION.log"

    local TOOL_NAME=${ARCH}-linux-android
    local TOOLCHAIN_ROOT_PATH=$BUILD_DIR/toolchains/${TOOL_NAME}
    local TOOLCHAIN_PATH=$TOOLCHAIN_ROOT_PATH/bin
    local NDK_TOOLCHAIN_BASENAME=$TOOLCHAIN_PATH/$TOOLCHAIN_NAME
    echo "NDK_TOOLCHAIN_BASENAME ${NDK_TOOLCHAIN_BASENAME}"

    # indicate new build
    echo ">>>"
    echo "Begin: $(date)"
	# folder, zip, target, target dir
    unarchive $OPENSSL_NAME $OPENSSL_PATH "android-$ABI" $SRC_DIR
    
    if [ -d $TOOLCHAIN_PATH ]; then
        echo "toolchain ${TOOL_NAME} exists"
    else
        echo "toolchain ${TOOL_NAME} missing, create it"
        $ANDROID_NDK_HOME/build/tools/make-standalone-toolchain.sh \
        --platform=android-$ANDROID_SDK \
        --stl=libc++ \
        --arch=$ARCH \
        --install-dir=$TOOLCHAIN_ROOT_PATH \
        --verbose
    fi

    export SYSROOT=$TOOLCHAIN_ROOT_PATH/sysroot
    export CC="$NDK_TOOLCHAIN_BASENAME-gcc --sysroot=${SYSROOT}"
    export CXX=$NDK_TOOLCHAIN_BASENAME-gcc++
    export LINK=${CXX} 
    export LD=$NDK_TOOLCHAIN_BASENAME-ld
    export AR=$NDK_TOOLCHAIN_BASENAME-ar
    export AS=$NDK_TOOLCHAIN_BASENAME-as
    export RANLIB=$NDK_TOOLCHAIN_BASENAME-ranlib
    export STRIP=$NDK_TOOLCHAIN_BASENAME-strip
    
    export ARCH_FLAGS=$5
    export ARCH_LINK=$6 
    export CPPFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing " 
    export CXXFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -frtti -fexceptions " 
    export CFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing " 
    export LDFLAGS=" ${ARCH_LINK} "

	echo "Configuring android-$ABI"
	(cd "$SRC_DIR"; ./Configure $OPENSSL_CONFIG_OPTIONS -DOPENSSL_PIC -fPIC "$COMPILER" > "$LOG_FILE" 2>&1)

    echo "Building android-$ABI..."
	(cd "$SRC_DIR"; make build_libs >> "$LOG_FILE" 2>&1)

	clear_android_env
    echo "Finished: $(date)"
}

function build_android {

	log_title "Android Build"

	local X86_ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse" 
	local ARMV7_ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
	local ARMV7_ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8" 
	local ARM_ARCH_FLAGS="-mthumb"

	# abi, arch, toolchain, openssl-config, arch_flags, arch_link
	#build_android_arch 'arm64-v8a' 'arm64' 'aarch64-linux-android' 'android' || exit 1
	#build_android_arch 'armeabi-v7a' 'arm' 'arm-linux-androideabi' 'android-armv7' $ARMV7_ARCH_FLAGS $ARMV7_ARCH_LINK || exit 2
	#build_android_arch 'armeabi' 'arm' 'arm-linux-androideabi' 'android' $ARM_ARCH_FLAGS || exit 3
	#build_android_arch 'x86' 'x86' 'i686-linux-android' 'android-x86' $X86_ARCH_FLAGS || exit 4
	build_android_arch 'x86_64' 'x86_64' 'x86_64-linux-android' 'android' || exit 5
}

function distribute_android {
    echo ">>>"
	echo "Distribute Android"

    local PLATFORM="Android"
    local NAME="$OPENSSL_NAME-$PLATFORM"
    local DIR="$DIST_DIR/$NAME/openssl"
	local ANDROID_ABIS="armeabi-v7a"
	
	for ABI in $ANDROID_ABIS; do
		local ABI_DIR=$DIR/$ABI
    	mkdir -p $ABI_DIR/include
    	mkdir -p $ABI_DIR/lib

		cp -LR $BUILD_DIR/android-$ABI/include/* $ABI_DIR/include
		cp -LR $BUILD_DIR/android-$ABI/libcrypto.a $ABI_DIR/lib
		cp -LR $BUILD_DIR/android-$ABI/libssl.a $ABI_DIR/lib
    done
}

## --------------------
## Build (Main)
## --------------------
clear_android_env
build_android
#distribute_android