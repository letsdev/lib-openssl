#!/bin/bash
set -e

## --------------------
## Parameters
## --------------------

VERSION=$1
IOS_SDK=11.2
MIN_IOS=7.0
ANDROID_SDK=21
IOS_ARCHS="i386 x86_64 armv7 armv7s arm64"
OPENSSL_CONFIG_OPTIONS="-no-asm"

if [ -z $VERSION ]; then
    echo "Missing VERSION as first parameter"
    exit 99
fi

## --------------------
## Variables
## --------------------

DEVELOPER_DIR=`xcode-select -print-path`
if [ ! -d $DEVELOPER_DIR ]; then
    echo "Please set up Xcode correctly. '$DEVELOPER_DIR' is not a valid developer tools folder."
    exit 1
fi
if [ ! -d "$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$IOS_SDK.sdk" ]; then
    echo "The iOS SDK $IOS_SDK was not found."
    exit 1
fi

if [ ! -d "${ANDROID_NDK_HOME}" ]; then
  echo "ANDROID_NDK_HOME not defined or directory does not exist"
  exit 1
fi

BASE_DIR=`pwd`
BUILD_DIR="$BASE_DIR/build"
DIST_DIR="$BASE_DIR/dist"
FILES_DIR="$BASE_DIR/files"

# Create folders
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$FILES_DIR"

OPENSSL_NAME="openssl-$VERSION"
OPENSSL_FILE="$OPENSSL_NAME.tar.gz"
OPENSSL_URL="http://www.openssl.org/source/$OPENSSL_FILE"
OPENSSL_PATH="$FILES_DIR/$OPENSSL_FILE"

## --------------------
## OpenSSL
## --------------------
if [ ! -e "$OPENSSL_PATH" ]; then
    curl -L "$OPENSSL_URL" -o "$OPENSSL_PATH"
fi

## --------------------
## Functions
## --------------------

function log_title() {
	echo '################################################'
	echo "$1"
	echo '################################################'
}

function unarchive() {
    if [ -z $1 ]; then
        echo "Missing extracted directory name to move"
        exit 21
    elif [ -z $2 ]; then
        echo "Missing ZIP file to extract"
        exit 22
    elif [ -z $3 ]; then
        echo "Missing target name"
        exit 23
    elif [ -z $4 ]; then
        echo "Missing target directory"
        exit 24
    fi
    
    EXTRACTED_NAME=$1
    ZIP_PATH=$2
    TARGET=$3
    TARGET_DIR=$4

	if [ -d $TARGET_DIR ]; then
		echo "Remove unarchive target dir for $TARGET"
		rm -dr $TARGET_DIR
	fi
    
    echo "Unarchive sources for $TARGET..."
    (cd $BUILD_DIR; tar -zxf $ZIP_PATH; mv $EXTRACTED_NAME $TARGET_DIR;) || exit 29
}

function build_ios() {

	log_title "iOS Build"
	echo "Using iOS SDK ${IOS_SDK}"
	echo "Using iOS min version ${MIN_IOS}"
    
	for ARCH in $IOS_ARCHS; do
        local PLATFORM="iPhoneOS"
        local COMPILER="iphoneos-cross"

        if [[ "$ARCH" == "i386" || "$ARCH" == "x86_64" ]]; then
            PLATFORM="iPhoneSimulator"
        fi

        local SRC_DIR="$BUILD_DIR/$PLATFORM-$ARCH"
        local LOG_FILE="$SRC_DIR/$PLATFORM$IOS_SDK-$ARCH.log"
        
        export CROSS_TOP="$DEVELOPER_DIR/Platforms/$PLATFORM.platform/Developer"
        export CROSS_SDK="$PLATFORM$IOS_SDK.sdk"
        export CC="clang -arch $ARCH -fembed-bitcode"
        # indicate new build
        echo ">>>"
		# folder, zip, target, target dir
        unarchive $OPENSSL_NAME $OPENSSL_PATH "$PLATFORM-$ARCH" $SRC_DIR

   		echo "Configuring $PLATFORM-$ARCH..."
        (cd "$SRC_DIR"; ./Configure $OPENSSL_CONFIG_OPTIONS "$COMPILER" > "$LOG_FILE" 2>&1)
        
        # Patch Makefile
        if [ "$ARCH" == "x86_64" ]; then
            sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -DOPENSSL_NO_ASM -/" "$SRC_DIR/Makefile"
        else
            sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -/" "$SRC_DIR/Makefile"
        fi
        # Patch versions
        #sed -ie "s/^# define OPENSSL_VERSION_NUMBER.*$/# define OPENSSL_VERSION_NUMBER  $FAKE_NIBBLE/" "$SRC_DIR/crypto/opensslv.h"
        #sed -ie "s/^#  define OPENSSL_VERSION_TEXT.*$/#  define OPENSSL_VERSION_TEXT  \"$FAKE_TEXT\"/" "$SRC_DIR/crypto/opensslv.h"
        
    	echo "Building $PLATFORM-$ARCH..."
    	(cd "$SRC_DIR"; make >> "$LOG_FILE" 2>&1)

		unset CROSS_TOP
		unset CROSS_SDK
		unset CC
    done
}

function distribute_ios() {
    echo ">>>"
	echo "Distribute iOS"

    local PLATFORM="iOS"
    local NAME="$OPENSSL_NAME-$PLATFORM"
    local DIR="$DIST_DIR/$NAME/openssl"
    local FILES="libcrypto.a libssl.a"
    mkdir -p "$DIR/include"
    mkdir -p "$DIR/lib"
    
    #echo "$VERSION" > "$DIR/VERSION"
    #cp "$BUILD_DIR/iPhoneSimulator-i386/LICENSE" "$DIR"
    cp -LR "$BUILD_DIR/iPhoneSimulator-i386/include/" "$DIR/include"
    
    # Alter rsa.h to make Swift happy
    sed -i .bak 's/const BIGNUM \*I/const BIGNUM *i/g' "$DIR/include/openssl/rsa.h"
    
    for f in $FILES; do
        lipo -create \
        "$BUILD_DIR/iPhoneSimulator-i386/$f" \
        "$BUILD_DIR/iPhoneSimulator-x86_64/$f" \
        "$BUILD_DIR/iPhoneOS-arm64/$f" \
        "$BUILD_DIR/iPhoneOS-armv7/$f" \
        "$BUILD_DIR/iPhoneOS-armv7s/$f" \
        -output "$DIR/lib/$f"
    done

	echo "Create iOS-Framework"
	local FRAMEWORK_DIR=$DIST_DIR/Framework-iOS
	mkdir -p $FRAMEWORK_DIR/Openssl.framework/Headers
 	mkdir -p $FRAMEWORK_DIR/Ssl.framework/Headers
	mkdir -p $FRAMEWORK_DIR/Crypto.framework

	cp -LR $DIR/include/openssl/ $FRAMEWORK_DIR/Openssl.framework/Headers/
	cp -LR $DIR/include/openssl/ $FRAMEWORK_DIR/Ssl.framework/Headers/

	cp $DIR/lib/libssl.a $FRAMEWORK_DIR/Openssl.framework/ssl
	cp $DIR/lib/libssl.a $FRAMEWORK_DIR/Ssl.framework/ssl
	cp $DIR/lib/libcrypto.a $FRAMEWORK_DIR/Openssl.framework/crypto
	cp $DIR/lib/libcrypto.a $FRAMEWORK_DIR/Crypto.framework/crypto
}

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

    local ABI=$1
    local ARCH=$2
    local TOOL_NAME=$3
    local COMPILER=$4

    local SRC_DIR=${BUILD_DIR}/android-$ABI
    local LOG_FILE="$SRC_DIR/android-$ABI-$VERSION.log"

    local TOOLCHAIN_ROOT_PATH=$BUILD_DIR/toolchains/${TOOL_NAME}
    local TOOLCHAIN_PATH=$TOOLCHAIN_ROOT_PATH/bin
    local NDK_TOOLCHAIN_BASENAME=$TOOLCHAIN_PATH/$TOOL_NAME

    # indicate new build
    echo ">>>"
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
    export CC="$NDK_TOOLCHAIN_BASENAME-clang --sysroot=$SYSROOT"
    export CXX=$NDK_TOOLCHAIN_BASENAME-clang++
    export LINK=${CXX} 
    export LD=$NDK_TOOLCHAIN_BASENAME-ld
    export AR=$NDK_TOOLCHAIN_BASENAME-ar
    export AS=$NDK_TOOLCHAIN_BASENAME-as
    export RANLIB=$NDK_TOOLCHAIN_BASENAME-ranlib
    export STRIP=$NDK_TOOLCHAIN_BASENAME-strip
    export CROSS_COMPILE=$TOOL_NAME
    
    export ARCH_FLAGS=$5
    export ARCH_LINK=$6 
    export CPPFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
    export CXXFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -frtti -fexceptions " 
    export CFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
    export LDFLAGS=" ${ARCH_LINK} "

	echo "Configuring android-$ABI"
	(cd "$SRC_DIR"; ./Configure $OPENSSL_CONFIG_OPTIONS -DOPENSSL_PIC -fPIC --cross-compile=$CROSS_COMPILE "$COMPILER" > "$LOG_FILE" 2>&1)

    echo "Building android-$ABI..."
	(cd "$SRC_DIR"; make build_libs >> "$LOG_FILE" 2>&1)

	clear_android_env
}

function build_android {

	log_title "Android Build"

	local X86_ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse" 
	local ARMV7_ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
	local ARMV7_ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8" 
	local ARM_ARCH_FLAGS="-mthumb"

	# abi, arch, toolchain, openssl-config, arch_flags, arch_link
	build_android_arch 'arm64-v8a' 'arm64' 'aarch64-linux-android' 'android64-aarch64' || exit 1
	build_android_arch 'armeabi-v7a' 'arm' 'arm-linux-androideabi' 'android' $ARMV7_ARCH_FLAGS $ARMV7_ARCH_LINK || exit 2
	build_android_arch 'armeabi' 'arm' 'arm-linux-androideabi' 'android' $ARM_ARCH_FLAGS || exit 3
	build_android_arch 'x86' 'x86' 'i686-linux-android' 'android-x86' $X86_ARCH_FLAGS || exit 4
	build_android_arch 'x86_64' 'x86_64' 'x86_64-linux-android' 'android64' || exit 5
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

build_ios
distribute_ios
build_android
distribute_android