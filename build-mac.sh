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

MAC_SDK=10.15
# i386 not working
MAC_ARCHS="x86_64"

## --------------------
## Variables
## --------------------

DEVELOPER_DIR=`xcode-select -print-path`
if [[ ! -d ${DEVELOPER_DIR} ]]; then
    echo "Please set up Xcode correctly. '${DEVELOPER_DIR}' is not a valid developer tools folder."
    exit 1
fi

if [[ ! -d "${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${MAC_SDK}.sdk" ]]; then
    echo "The MacOSX SDK ${MAC_SDK} was not found."
    exit 1
fi

## --------------------
## Functions
## --------------------

function build_mac() {

	log_title "Mac Build"
	echo "Using Mac SDK ${MAC_SDK}"
	echo "Xcode Developer directory ${DEVELOPER_DIR}"

	for ARCH in ${MAC_ARCHS}; do
        log_title "$ARCH"
        local PLATFORM="MacOSX"
        local COMPILER="darwin64-x86_64-cc"
        if [[ "${ARCH}" == "i386" ]]; then
            COMPILER="darwin-i386-cc"
        fi

        local SRC_DIR="${BUILD_DIR}/${PLATFORM}-${ARCH}"
        local LOG_FILE="${SRC_DIR}/${PLATFORM}${MAC_SDK}-${ARCH}.log"

        export CROSS_TOP="${DEVELOPER_DIR}/Platforms/${PLATFORM}.platform/Developer"
        export CROSS_SDK="${PLATFORM}${MAC_SDK}.sdk"
        export CC="clang"

        # indicate new build
        echo ">>>"
		# folder, zip, target, target dir
        unarchive ${OPENSSL_NAME} ${OPENSSL_PATH} "${PLATFORM}-${ARCH}" ${SRC_DIR}

        local TARGET_PATCH_FILE="${SRC_DIR}/Configurations/10-main.conf"
        echo "Patch ${TARGET_PATCH_FILE}"
        patch ${TARGET_PATCH_FILE} "./10-main.conf.patch"

   		echo "Configuring ${PLATFORM}-${ARCH}..."
        (cd "${SRC_DIR}"; ./Configure no-asm no-tests "${COMPILER}" > "${LOG_FILE}" 2>&1)

        local TARGET_PATCH_FILE="${SRC_DIR}/Makefile"
        echo "Patch ${TARGET_PATCH_FILE}"
        patch ${TARGET_PATCH_FILE} "./Makefile-mac.patch"

    	echo "Building ${PLATFORM}-${ARCH}..."
    	(cd "${SRC_DIR}"; make build_libs >> "${LOG_FILE}" 2>&1)

		unset CROSS_TOP
		unset CROSS_SDK
		unset CC
    done
}

function distribute_mac() {
    log_title "Distribute Mac"

    local PLATFORM="MacOSX"
    local NAME="${PLATFORM}"
    local DIR="${DIST_DIR}/${NAME}/openssl"
    local FILES="libcrypto.a libssl.a"
    mkdir -p "${DIR}/include"
    mkdir -p "${DIR}/lib"

    #echo "$VERSION" > "$DIR/VERSION"
    cp -LR "${BUILD_DIR}/MacOSX-x86_64/include/" "${DIR}/include"

    # Alter rsa.h to make Swift happy
    sed -i .bak 's/const BIGNUM \*I/const BIGNUM *i/g' "${DIR}/include/openssl/rsa.h"

    echo "Combine library files"
    for f in ${FILES}; do
        local OUTPUT_FILE=${DIR}/lib/${f}
        lipo -create \
        "${BUILD_DIR}/MacOSX-x86_64/${f}" \
        -output "${OUTPUT_FILE}"
        echo "Created ${OUTPUT_FILE}"
        echo "Architectues: $(lipo -info ${OUTPUT_FILE})"
    done

	echo "Create Mac-Framework"
	local FRAMEWORK_DIR=${DIST_DIR}/Framework-Mac
	mkdir -p ${FRAMEWORK_DIR}/Openssl.framework/Headers
 	mkdir -p ${FRAMEWORK_DIR}/Ssl.framework/Headers
	mkdir -p ${FRAMEWORK_DIR}/Crypto.framework

	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR}/Openssl.framework/Headers/
	cp -LR ${DIR}/include/openssl/ ${FRAMEWORK_DIR}/Ssl.framework/Headers/

	copy "${DIR}/lib/libssl.a" "${FRAMEWORK_DIR}/Openssl.framework/ssl"
	copy "${DIR}/lib/libssl.a" "${FRAMEWORK_DIR}/Ssl.framework/ssl"
	copy "${DIR}/lib/libcrypto.a" "${FRAMEWORK_DIR}/Openssl.framework/crypto"
	copy "${DIR}/lib/libcrypto.a" "${FRAMEWORK_DIR}/Crypto.framework/crypto"
}

function copy() {
    echo "Copy ${1} => ${2}"
    cp "$1" "$2"
}

## --------------------
## Build (Main)
## --------------------

build_mac
distribute_mac
