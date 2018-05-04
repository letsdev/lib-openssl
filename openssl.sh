#!/bin/bash

###############################################################################
##                                                                           ##
## Build and package OpenSSL static libraries for OSX/iOS                    ##
##                                                                           ##
## This script is in the public domain.                                      ##
## Creator     : Laurent Etiemble                                            ##
##                                                                           ##
###############################################################################

## --------------------
## Parameters
## --------------------

VERSION=1.0.2o
IOS_SDK=11.2
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

BASE_DIR=`pwd`
BUILD_DIR="$BASE_DIR/build"
DIST_DIR="$BASE_DIR/dist"
FILES_DIR="$BASE_DIR/files"

OPENSSL_NAME="openssl-$VERSION"
OPENSSL_FILE="$OPENSSL_NAME.tar.gz"
OPENSSL_URL="http://www.openssl.org/source/$OPENSSL_FILE"
OPENSSL_PATH="$FILES_DIR/$OPENSSL_FILE"

## --------------------
## Main
## --------------------

_unarchive() {
	# Expand source tree if needed
	if [ ! -d "$SRC_DIR" ]; then
		echo "Unarchive sources for $PLATFORM-$ARCH..."
		(cd "$BUILD_DIR"; tar -zxf "$OPENSSL_PATH"; mv "$OPENSSL_NAME" "$SRC_DIR";)
	fi
}

_configure() {
	# Configure
	echo "Configuring $PLATFORM-$ARCH..."
	(cd "$SRC_DIR"; CROSS_TOP="$CROSS_TOP" CROSS_SDK="$CROSS_SDK" CC="$CC" ./Configure --prefix="$DST_DIR" -no-apps "$COMPILER" > "$LOG_FILE" 2>&1)
}

_build() {
	# Build
	echo "Building $PLATFORM-$ARCH..."
	(cd "$SRC_DIR"; CROSS_TOP="$CROSS_TOP" CROSS_SDK="$CROSS_SDK" CC="$CC" make >> "$LOG_FILE" 2>&1)
}

build_ios() {
	for ARCH in $IOS_ARCHS; do
		PLATFORM="iPhoneOS"
		COMPILER="iphoneos-cross"
		SRC_DIR="$BUILD_DIR/$PLATFORM-$ARCH"
		DST_DIR="$DIST_DIR/$PLATFORM-$ARCH"
		LOG_FILE="$SRC_DIR/$PLATFORM$IOS_SDK-$ARCH.log"

		# Select the compiler
		if [ "$ARCH" == "i386" ]; then
			PLATFORM="iPhoneSimulator"
			MIN_IOS="4.2"
		elif [ "$ARCH" == "x86_64" ]; then
			PLATFORM="iPhoneSimulator"
			MIN_IOS="7.0"
		elif [ "$ARCH" == "arm64" ]; then
			MIN_IOS="7.0"
		else
			MIN_IOS="6.0"
		fi

		CROSS_TOP="$DEVELOPER_DIR/Platforms/$PLATFORM.platform/Developer"
		CROSS_SDK="$PLATFORM$IOS_SDK.sdk"
		CC="clang -arch $ARCH -fembed-bitcode"

		_unarchive
		_configure

		# Patch Makefile
		if [ "$ARCH" == "x86_64" ]; then
			sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -DOPENSSL_NO_ASM -/" "$SRC_DIR/Makefile"
    	else
			sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -/" "$SRC_DIR/Makefile"
        fi
		# Patch versions
		#sed -ie "s/^# define OPENSSL_VERSION_NUMBER.*$/# define OPENSSL_VERSION_NUMBER  $FAKE_NIBBLE/" "$SRC_DIR/crypto/opensslv.h"
		#sed -ie "s/^#  define OPENSSL_VERSION_TEXT.*$/#  define OPENSSL_VERSION_TEXT  \"$FAKE_TEXT\"/" "$SRC_DIR/crypto/opensslv.h"

		_build
	done
}

distribute_ios() {
	PLATFORM="iOS"
	NAME="$OPENSSL_NAME-$PLATFORM"
	DIR="$DIST_DIR/$NAME"
	FILES="libcrypto.a libssl.a"
	mkdir -p "$DIR/include"
	mkdir -p "$DIR/lib"

	echo "$VERSION" > "$DIR/VERSION"
	cp "$BUILD_DIR/iPhoneOS-i386/LICENSE" "$DIR"
	cp -LR "$BUILD_DIR/iPhoneOS-i386/include/" "$DIR/include"

	# Alter rsa.h to make Swift happy
	sed -i .bak 's/const BIGNUM \*I/const BIGNUM *i/g' "$DIR/include/openssl/rsa.h"

	for f in $FILES; do
		lipo -create \
			"$BUILD_DIR/iPhoneOS-i386/$f" \
			"$BUILD_DIR/iPhoneOS-x86_64/$f" \
			"$BUILD_DIR/iPhoneOS-arm64/$f" \
			"$BUILD_DIR/iPhoneOS-armv7/$f" \
			"$BUILD_DIR/iPhoneOS-armv7s/$f" \
			-output "$DIR/lib/$f"
	done
}

# Create folders
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$FILES_DIR"

# Retrieve OpenSSL tarbal if needed
if [ ! -e "$OPENSSL_PATH" ]; then
	curl -L "$OPENSSL_URL" -o "$OPENSSL_PATH"
fi

build_ios
distribute_ios
