#!/bin/bash
set -e

## --------------------
## Parameters
## --------------------

VERSION=$1
IOS_SDK=11.2
MIN_IOS=7.0
IOS_ARCHS="i386 x86_64 armv7 armv7s arm64"

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
    
    # Expand source tree if needed
    if [ ! -d $TARGET_DIR ]; then
        echo "Unarchive sources for $TARGET..."
        (cd $BUILD_DIR; tar -zxf $ZIP_PATH; mv $EXTRACTED_NAME $TARGET_DIR;) || exit 29
    fi
}

function build_ios() {
	echo "Begin iOS Build"
	echo "Using iOS SDK ${IOS_SDK}"
	echo "Using iOS min version ${MIN_IOS}"
    
	for ARCH in $IOS_ARCHS; do
        local PLATFORM="iPhoneOS"
        local COMPILER="iphoneos-cross"

        if [[ "$ARCH" == "i386" || "$ARCH" == "x86_64" ]]; then
            PLATFORM="iPhoneSimulator"
        fi

        local SRC_DIR="$BUILD_DIR/$PLATFORM-$ARCH"
        local DST_DIR="$DIST_DIR/$PLATFORM-$ARCH"
        local LOG_FILE="$SRC_DIR/$PLATFORM$IOS_SDK-$ARCH.log"
        
        export CROSS_TOP="$DEVELOPER_DIR/Platforms/$PLATFORM.platform/Developer"
        export CROSS_SDK="$PLATFORM$IOS_SDK.sdk"
        export CC="clang -arch $ARCH -fembed-bitcode"
        
        # indicate new build
        echo ">>>"
		# folder, zip, target, target dir
        unarchive $OPENSSL_NAME $OPENSSL_PATH "$PLATFORM-$ARCH" $SRC_DIR

   		echo "Configuring $PLATFORM-$ARCH..."
        (cd "$SRC_DIR"; ./Configure --prefix="$DST_DIR" -no-apps "$COMPILER" > "$LOG_FILE" 2>&1)
        
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
	echo "Distribute iOS"

    local PLATFORM="iOS"
    local NAME="$OPENSSL_NAME-$PLATFORM"
    local DIR="$DIST_DIR/$NAME"
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

## --------------------
## Build (Main)
## --------------------

build_ios
distribute_ios
