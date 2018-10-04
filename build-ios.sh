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

IOS_SDK=12.0
MIN_IOS=7.0
IOS_ARCHS="i386 x86_64 armv7 armv7s arm64"

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

## --------------------
## Functions
## --------------------

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
    
    echo "Combine library files"
    for f in $FILES; do
        local OUTPUT_FILE=$DIR/lib/$f
        lipo -create \
        "$BUILD_DIR/iPhoneSimulator-i386/$f" \
        "$BUILD_DIR/iPhoneSimulator-x86_64/$f" \
        "$BUILD_DIR/iPhoneOS-arm64/$f" \
        "$BUILD_DIR/iPhoneOS-armv7/$f" \
        "$BUILD_DIR/iPhoneOS-armv7s/$f" \
        -output $OUTPUT_FILE
        echo "Created $OUTPUT_FILE"
    done

	echo "Create iOS-Framework"
	local FRAMEWORK_DIR=$DIST_DIR/Framework-iOS
	mkdir -p $FRAMEWORK_DIR/Openssl.framework/Headers
 	mkdir -p $FRAMEWORK_DIR/Ssl.framework/Headers
	mkdir -p $FRAMEWORK_DIR/Crypto.framework

	copy -LR $DIR/include/openssl/ $FRAMEWORK_DIR/Openssl.framework/Headers/
	copy -LR $DIR/include/openssl/ $FRAMEWORK_DIR/Ssl.framework/Headers/

	copy $DIR/lib/libssl.a $FRAMEWORK_DIR/Openssl.framework/ssl
	copy $DIR/lib/libssl.a $FRAMEWORK_DIR/Ssl.framework/ssl
	copy $DIR/lib/libcrypto.a $FRAMEWORK_DIR/Openssl.framework/crypto
	copy $DIR/lib/libcrypto.a $FRAMEWORK_DIR/Crypto.framework/crypto
}

function copy() {
    echo "Copy >> $1 >> $2"
    cp $1 $2
}

## --------------------
## Build (Main)
## --------------------

build_ios
distribute_ios