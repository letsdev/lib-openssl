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

ANDROID_SDK=28
ANDROID_MIN_SDK=21

## --------------------
## Variables
## --------------------

if [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
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
    log_title "${1}"
    if [[ -z $1 ]]; then
        echo 'no ABI set'
        exit 1
        elif [[ -z $2 ]]; then
        echo 'no ARCH set'
        exit 1
        elif [[ -z $3 ]]; then
        echo 'no toolchain name set'
        exit 1
    fi
    local ABI=$1
    local ARCH=$2
    local TOOLCHAIN_NAME=$3
    local COMPILER=$4

    local SRC_DIR=${BUILD_DIR}/android-${ABI}
    local LOG_FILE="$SRC_DIR/android-${ABI}-${VERSION}.log"

    HOST_TAG=$(host_tag)
    echo ${HOST_TAG}

    local TOOLCHAIN_ROOT_PATH=${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${HOST_TAG}
    local CLANG_TOOLCHAIN=${TOOLCHAIN_NAME}
    if [[ ${ABI} == "armeabi-v7a" ]]; then
        local V7A_BIN="armv7a-linux-androideabi"
        echo "Update clang ${ABI} bin toolchain name to ${V7A_BIN}"
        CLANG_TOOLCHAIN=${V7A_BIN}
    fi
    local NDK_TOOLCHAIN_BASENAME="${TOOLCHAIN_ROOT_PATH}/bin/${TOOLCHAIN_NAME}"
    local NDK_TOOLCHAIN_CLANG_BASENAME="${TOOLCHAIN_ROOT_PATH}/bin/${CLANG_TOOLCHAIN}"
    local CMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake
    echo "NDK_TOOLCHAIN_BASENAME ${NDK_TOOLCHAIN_BASENAME}"

    # indicate new build
    echo ">>>"
    echo "Begin: $(date)"
	# folder, zip, target, target dir
    unarchive ${OPENSSL_NAME} ${OPENSSL_PATH} "android-${ABI}" ${SRC_DIR}
    local TARGET_PATCH_CONFIGURE="${SRC_DIR}/Configure"
    echo "Applying Patch for ${TARGET_PATCH_CONFIGURE}"
    patch ${TARGET_PATCH_CONFIGURE} patches/Configure.patch

    export SYSROOT=${TOOLCHAIN_ROOT_PATH}/sysroot
    export CC="${NDK_TOOLCHAIN_CLANG_BASENAME}${ANDROID_SDK}-clang --sysroot=${SYSROOT}"
    export CXX=${NDK_TOOLCHAIN_CLANG_BASENAME}${ANDROID_SDK}-clang++
    export LINK=${CXX} 
    export LD=${NDK_TOOLCHAIN_BASENAME}-ld
    export AR=${NDK_TOOLCHAIN_BASENAME}-ar
    export AS=${NDK_TOOLCHAIN_BASENAME}-as
    export RANLIB=${NDK_TOOLCHAIN_BASENAME}-ranlib
    export STRIP=${NDK_TOOLCHAIN_BASENAME}-strip

    export ARCH_FLAGS=$5
    export ARCH_LINK=$6 
    export CPPFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -I${SYSROOT}/usr/include/${TOOLCHAIN_NAME}"
    export CXXFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -frtti -fexceptions -I${SYSROOT}/usr/include/${TOOLCHAIN_NAME}"
    export CFLAGS=" ${ARCH_FLAGS} -fPIC -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -I${SYSROOT}/usr/include/${TOOLCHAIN_NAME}"
    export LDFLAGS=" ${ARCH_LINK} "

	echo "Configuring android-${ABI}"
	(cd "${SRC_DIR}"; ./Configure ${OPENSSL_CONFIG_OPTIONS} -DOPENSSL_PIC -fPIC -no-stdio "${COMPILER}" > "${LOG_FILE}" 2>&1)

    local TARGET_PATCH_MAKEFILE="${SRC_DIR}/Makefile"
    echo "Applying Patch for ${TARGET_PATCH_MAKEFILE}"
    patch ${TARGET_PATCH_MAKEFILE} patches/Makefile-${ABI}.patch

    echo "Building android-${ABI}..."
	(cd "${SRC_DIR}"; make build_libs "CMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}" >> "${LOG_FILE}" 2>&1)

	clear_android_env
    check_files ${ABI} ${LOG_FILE}
    echo "Finished: $(date)"
}

function build_android {

	log_title "Android Build"

	local X86_ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse" 
	local ARMV7_ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
	local ARMV7_ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8" 
	local ARM_ARCH_FLAGS="-mthumb"

	# abi, arch, toolchain, openssl-config, arch_flags, arch_link
	build_android_arch 'arm64-v8a' 'arm64' 'aarch64-linux-android' 'android'
	build_android_arch 'armeabi-v7a' 'arm' 'arm-linux-androideabi' 'android-armv7' ${ARMV7_ARCH_FLAGS} ${ARMV7_ARCH_LINK}
	build_android_arch 'x86' 'x86' 'i686-linux-android' 'android-x86' ${X86_ARCH_FLAGS}
	build_android_arch 'x86_64' 'x86_64' 'x86_64-linux-android' 'android'
}

function check_files() {
    local FILE_SSL=${BUILD_DIR}/android-$1/libssl.a
    local FILE_CRYPTO=${BUILD_DIR}/android-$1/libcrypto.a
    if [[ ! -f ${FILE_SSL} ]]; then
        echo "Missing ${FILE_SSL}"
        cat $2
        exit 1
    fi
    if [[ ! -f ${FILE_CRYPTO} ]]; then
        echo "Missing ${FILE_CRYPTO}"
        cat $2
        exit 2
    fi
    echo "$1 successful"
}

function distribute_android {
    log_title "Distribute Android"

    local PLATFORM="Android"
    local NAME="${PLATFORM}"
    local DIR="${DIST_DIR}/${NAME}/openssl"
	local ANDROID_ABIS="arm64-v8a armeabi-v7a x86 x86_64"
	
	for ABI in ${ANDROID_ABIS}; do
		local ABI_DIR=${DIR}/${ABI}
    	mkdir -p ${ABI_DIR}/include
    	mkdir -p ${ABI_DIR}/lib

        echo "Copy ${ABI}"
		cp -LR ${BUILD_DIR}/android-${ABI}/include/* ${ABI_DIR}/include
		cp ${BUILD_DIR}/android-${ABI}/libcrypto.a ${ABI_DIR}/lib/libcrypto.a
		cp ${BUILD_DIR}/android-${ABI}/libssl.a ${ABI_DIR}/lib/libssl.a
    done
}

function host_tag {
    local name=`uname`
    local result
    if [[ ${name} =~ "Darwin" ]]; then
        result="darwin-x86_64"
    elif [[ ${name} =~ "Linux" ]]; then
        result="linux-x86_64"
    else
        echo "Can't find matching host tag for ${name}"
        exit 1
    fi
    echo ${result}
}

## --------------------
## Build (Main)
## --------------------

clear_android_env
build_android
distribute_android
