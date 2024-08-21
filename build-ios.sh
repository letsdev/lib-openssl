#!/usr/bin/env bash
set -e

VERSION=$1

if [[ -z ${VERSION} ]]; then
    echo "Missing VERSION as first parameter"
    exit 99
fi

. ./common.sh #source-only
download_openssl

## --------------------
## Parameters
## --------------------

IOS_SDK=17.0
MIN_IOS=12.0
IOS_ARCHS="x86_64 arm64 sim_arm64"

## --------------------
## Variables
## --------------------

DEVELOPER_DIR=`xcode-select -print-path`
if [[ ! -d ${DEVELOPER_DIR} ]]; then
    echo "Please set up Xcode correctly. '${DEVELOPER_DIR}' is not a valid developer tools folder."
    exit 1
fi

if [[ ! -d "${DEVELOPER_DIR}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" ]]; then
    echo "The iOS SDK ${IOS_SDK} was not found."
    exit 1
fi

## --------------------
## Functions
## --------------------

function build_ios() {

	log_title "iOS Build"
	echo "Using iOS SDK ${IOS_SDK}"
	echo "Using iOS min version ${MIN_IOS}"
	echo "Xcode Developer directory ${DEVELOPER_DIR}"

	for ARCH in ${IOS_ARCHS}; do
        log_title "$ARCH"
        local PLATFORM="iPhoneOS"
        local COMPILER="iphoneos-cross"
        
        
        if [[ "$ARCH" == "arm64" || "$ARCH" == "arm64e" ]]; then
            COMPILER="ios64-cross"
            ADDITIONAL_CC_ARGUMENTS="-miphoneos-version-min=${MIN_IOS}"
        fi

        if [[ "$ARCH" == "i386" || "$ARCH" == "x86_64" || "$ARCH" == "sim_arm64" ]]; then
            PLATFORM="iPhoneSimulator"
            if [[ "$ARCH" == "sim_arm64" ]]; then
                ARCH="arm64"
                COMPILER="iossimulator-xcrun"
                ADDITIONAL_CC_ARGUMENTS="-mios-simulator-version-min=${MIN_IOS}"
            fi
        fi

        local SRC_DIR="${BUILD_DIR}/${PLATFORM}-${ARCH}"
        local LOG_FILE="${SRC_DIR}/${PLATFORM}${IOS_SDK}-${ARCH}.log"

        export CROSS_TOP="${DEVELOPER_DIR}/Platforms/${PLATFORM}.platform/Developer"
        export CROSS_SDK="${PLATFORM}.sdk"
        export CROSS_SYSROOT="${CROSS_TOP}/SDKs/${CROSS_SDK}"
        export CC="clang -arch ${ARCH} ${ADDITIONAL_CC_ARGUMENTS} -isysroot ${CROSS_SYSROOT}"
        # indicate new build
        echo ">>>"
        echo "Using CROSS_TOP: ${CROSS_TOP}"
        echo "Using CROSS_SDK: ${CROSS_SDK}"
        echo "Using CROSS_SYSROOT: ${CROSS_SYSROOT}"
		# folder, zip, target, target dir
        unarchive ${OPENSSL_NAME} ${OPENSSL_PATH} "${PLATFORM}-${ARCH}" ${SRC_DIR}

        #if [[ "$ARCH" == "arm64" ]]; then
      #    local TARGET_PATCH_FILE="${SRC_DIR}/Configurations/15-ios.conf"
    #      echo "Patch ${TARGET_PATCH_FILE}"
    #      patch ${TARGET_PATCH_FILE} "./15-ios.conf.patch"
    #    fi

   		echo "Configuring ${PLATFORM}-${ARCH}..."
        (cd "${SRC_DIR}"; ./Configure "${COMPILER}" ${OPENSSL_CONFIG_OPTIONS} > "${LOG_FILE}" 2>&1)

        # Patch Makefile
        if [[ "${ARCH}" == "x86_64" ]]; then
            sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -DOPENSSL_NO_ASM -/" "$SRC_DIR/Makefile"
        else
          sed -ie "s/^CFLAG= -/CFLAG=  -miphoneos-version-min=$MIN_IOS -/" "$SRC_DIR/Makefile"
        fi
        # Patch versions
        #sed -ie "s/^# define OPENSSL_VERSION_NUMBER.*$/# define OPENSSL_VERSION_NUMBER  $FAKE_NIBBLE/" "$SRC_DIR/crypto/opensslv.h"
        #sed -ie "s/^#  define OPENSSL_VERSION_TEXT.*$/#  define OPENSSL_VERSION_TEXT  \"$FAKE_TEXT\"/" "$SRC_DIR/crypto/opensslv.h"

    	echo "Building ${PLATFORM}-${ARCH}..."
    	(cd "${SRC_DIR}"; make >> "${LOG_FILE}" 2>&1)

		unset CROSS_TOP
		unset CROSS_SDK
		unset CC
    done
}

function distribute_ios() {
    log_title "Distribute iOS"

    local PLATFORM="iOS"
    local NAME="${PLATFORM}"
    local DIR="${DIST_DIR}/${NAME}/openssl"
    local FILES="libcrypto.a libssl.a"
    mkdir -p "${DIR}/include"
    mkdir -p "${DIR}/lib"

    #echo "$VERSION" > "$DIR/VERSION"
    #cp "$BUILD_DIR/iPhoneSimulator-i386/LICENSE" "$DIR"
    cp -LR "${BUILD_DIR}/iPhoneSimulator-x86_64/include/" "${DIR}/include"

    # Alter rsa.h to make Swift happy
    sed -i .bak 's/const BIGNUM \*I/const BIGNUM *i/g' "${DIR}/include/openssl/rsa.h"

    echo "Combine library files"
    for f in ${FILES}; do
        local OUTPUT_FILE=${DIR}/lib/${f}
        lipo -create \
        "${BUILD_DIR}/iPhoneSimulator-x86_64/${f}" \
        "${BUILD_DIR}/iPhoneSimulator-arm64/${f}" \
        -output ${OUTPUT_FILE}
        echo "Created ${OUTPUT_FILE}"
        echo "Architectues: $(lipo -info ${OUTPUT_FILE})"
    done

	echo "Create iOS-Framework "
	local FRAMEWORK_DIR=${DIST_DIR}/Framework-iOS
	mkdir -p ${FRAMEWORK_DIR}/Openssl.framework/Headers
 	mkdir -p ${FRAMEWORK_DIR}/Ssl.framework/Headers
	mkdir -p ${FRAMEWORK_DIR}/Crypto.framework

	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR}/Openssl.framework/Headers/
	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR}/Ssl.framework/Headers/
    cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR}/Crypto.framework/Headers/

	copy "${BUILD_DIR}/iPhoneOS-arm64/libssl.a" "${FRAMEWORK_DIR}/Openssl.framework/Ssl"
	copy "${BUILD_DIR}/iPhoneOS-arm64/libssl.a" "${FRAMEWORK_DIR}/Ssl.framework/Ssl"
	copy "${BUILD_DIR}/iPhoneOS-arm64/libcrypto.a" "${FRAMEWORK_DIR}/Openssl.framework/Crypto"
	copy "${BUILD_DIR}/iPhoneOS-arm64/libcrypto.a" "${FRAMEWORK_DIR}/Crypto.framework/Crypto"

	echo "Create iOS Simulator-Framework"
	local FRAMEWORK_DIR_SIMULATOR=${DIST_DIR}/Framework-Simulator
	mkdir -p ${FRAMEWORK_DIR_SIMULATOR}/Openssl.framework/Headers
 	mkdir -p ${FRAMEWORK_DIR_SIMULATOR}/Ssl.framework/Headers
	mkdir -p ${FRAMEWORK_DIR_SIMULATOR}/Crypto.framework

	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR_SIMULATOR}/Openssl.framework/Headers/
	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR_SIMULATOR}/Ssl.framework/Headers/
    cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR_SIMULATOR}/Crypto.framework/Headers/

	copy "${DIR}/lib/libssl.a" "${FRAMEWORK_DIR_SIMULATOR}/Openssl.framework/Ssl"
	copy "${DIR}/lib/libssl.a" "${FRAMEWORK_DIR_SIMULATOR}/Ssl.framework/Ssl"
	copy "${DIR}/lib/libcrypto.a" "${FRAMEWORK_DIR_SIMULATOR}/Openssl.framework/Crypto"
	copy "${DIR}/lib/libcrypto.a" "${FRAMEWORK_DIR_SIMULATOR}/Crypto.framework/Crypto"

    echo "Create xc-Frameworks xcodebuild"
	local XCFRAMEWORK_DIR=${DIST_DIR}/Framework-XC
	mkdir -p ${XCFRAMEWORK_DIR}
	
    xcodebuild -create-xcframework -framework ${FRAMEWORK_DIR_SIMULATOR}/Ssl.framework -framework ${FRAMEWORK_DIR}/Ssl.framework -output ${XCFRAMEWORK_DIR}/Ssl.xcframework
    xcodebuild -create-xcframework -framework ${FRAMEWORK_DIR_SIMULATOR}/Crypto.framework -framework ${FRAMEWORK_DIR}/Crypto.framework -output ${XCFRAMEWORK_DIR}/Crypto.xcframework
}

function copy() {
    echo "Copy ${1} => ${2}"
    cp $1 $2
}

## --------------------
## Build (Main)
## --------------------

build_ios
distribute_ios
