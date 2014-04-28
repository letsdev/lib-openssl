#!/bin/sh

#  Automatic build script for libssl and libcrypto 
#  for iPhoneOS and iPhoneSimulator
#
#  Created by Felix Schulze on 16.12.10.
#  Copyright 2010 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  Script adapted to include Android build by Arne Fischer
#
###########################################################################
#  Change values here													  #
#				                                                          #
VERSION="1.0.1g"													      #
SDKVERSION="7.1"														  #
#																		  #
###########################################################################
#																		  #
# Don't change anything under this line!								  #
#																		  #
###########################################################################



if [ -d "$1" ]; then
    CURRENTPATH="$1"
else
    CURRENTPATH=`pwd`
fi

ARCHS="i386 x86_64 armv7 armv7s arm64"
DEVELOPER=`xcode-select -print-path`

if [ ! -d "$DEVELOPER" ]; then
  echo "xcode path is not set correctly $DEVELOPER does not exist (most likely because of xcode > 4.3)"
  echo "run"
  echo "sudo xcode-select -switch <xcode path>"
  echo "for default installation:"
  echo "sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

case $DEVELOPER in  
     *\ * )
           echo "Your Xcode path contains whitespaces, which is not supported."
           exit 1
          ;;
esac

case $CURRENTPATH in  
     *\ * )
           echo "Your path contains whitespaces, which is not supported by 'make install'."
           exit 1
          ;;
esac


mkdir -p "${CURRENTPATH}/bin"
mkdir -p "${CURRENTPATH}/src"
mkdir -p "${CURRENTPATH}/lib"
mkdir -p "${CURRENTPATH}/lib/ios/"
mkdir -p "${CURRENTPATH}/lib/android/"
mkdir -p "${CURRENTPATH}/lib/android/libs"
mkdir -p "${CURRENTPATH}/lib/android/libs/armeabi"
mkdir -p "${CURRENTPATH}/lib/android/libs/armeabi-v7a"
mkdir -p "${CURRENTPATH}/lib/android/libs/x86"

echo "clear export flags"
export NDK=
export TOOL=
export NDK_TOOLCHAIN_BASENAME=
export CC=
export CXX=
export LINK=
export LD=
export AR=
export RANLIB=
export STRIP=
export ARCH_FLAGS=
export ARCH_LINK= 
export CPPFLAGS=
export CXXFLAGS= 
export CFLAGS=
export LDFLAGS=


echo "Copy sources to temp directory"

cp -r "${CURRENTPATH}/openssl-${VERSION}" "${CURRENTPATH}/src/openssl-${VERSION}"

cd "${CURRENTPATH}/src/openssl-${VERSION}"



for ARCH in ${ARCHS}
do
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]];
	then
		PLATFORM="iPhoneSimulator"
	else
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
		PLATFORM="iPhoneOS"
	fi
	
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${SDKVERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"

	echo "Building openssl-${VERSION} for ${PLATFORM} ${SDKVERSION} ${ARCH}"
	echo "Please stand by..."

	export CC="${BUILD_TOOLS}/usr/bin/gcc -arch ${ARCH}"
	mkdir -p "${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
	LOG="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/build-openssl-${VERSION}.log"

	set +e
    if [[ "$VERSION" =~ 1.0.0. ]]; then
	    ./Configure BSD-generic32 --openssldir="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" > "${LOG}" 2>&1
	elif [ "${ARCH}" == "x86_64" ]; then
	    ./Configure darwin64-x86_64-cc --openssldir="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" > "${LOG}" 2>&1
    else
	    ./Configure iphoneos-cross --openssldir="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" > "${LOG}" 2>&1
    fi
    
    if [ $? != 0 ];
    then 
    	echo "Problem while configure - Please check ${LOG}"
    	exit 1
    fi

	# add -isysroot to CC=
	sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=7.0 !" "Makefile"

	make >> "${LOG}" 2>&1
	
	if [ $? != 0 ];
    then 
    	echo "Problem while make - Please check ${LOG}"
    	exit 1
    fi
    
    set -e
	make install >> "${LOG}" 2>&1
	make clean >> "${LOG}" 2>&1
done

echo "Build library..."
lipo -create ${CURRENTPATH}/bin/iPhoneSimulator${SDKVERSION}-i386.sdk/lib/libssl.a ${CURRENTPATH}/bin/iPhoneSimulator${SDKVERSION}-x86_64.sdk/lib/libssl.a  ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-armv7.sdk/lib/libssl.a ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-armv7s.sdk/lib/libssl.a ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-arm64.sdk/lib/libssl.a -output ${CURRENTPATH}/lib/libssl.a

lipo -create ${CURRENTPATH}/bin/iPhoneSimulator${SDKVERSION}-i386.sdk/lib/libcrypto.a ${CURRENTPATH}/bin/iPhoneSimulator${SDKVERSION}-x86_64.sdk/lib/libcrypto.a ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-armv7.sdk/lib/libcrypto.a ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-armv7s.sdk/lib/libcrypto.a ${CURRENTPATH}/bin/iPhoneOS${SDKVERSION}-arm64.sdk/lib/libcrypto.a -output ${CURRENTPATH}/lib/libcrypto.a

mkdir -p ${CURRENTPATH}/include
cp -R ${CURRENTPATH}/bin/iPhoneSimulator${SDKVERSION}-i386.sdk/include/openssl ${CURRENTPATH}/include/
echo "Building done."

echo "Cleaning up..."

mv ${CURRENTPATH}/lib/*.a ${CURRENTPATH}/lib/ios/

echo 'create framework folder'
mkdir ${CURRENTPATH}/lib/ios/Openssl.framework
mkdir ${CURRENTPATH}/lib/ios/Ssl.framework
mkdir ${CURRENTPATH}/lib/ios/Crypto.framework

echo 'create header folder and copy headers'
mkdir ${CURRENTPATH}/lib/ios/Openssl.framework/Headers/
mkdir ${CURRENTPATH}/lib/ios/Ssl.framework/Headers/

cp ${CURRENTPATH}/include/openssl/* ${CURRENTPATH}/lib/ios/Openssl.framework/Headers/
cp ${CURRENTPATH}/include/openssl/* ${CURRENTPATH}/lib/ios/Ssl.framework/Headers/

echo 'copy lib binary'
cp ${CURRENTPATH}/lib/ios/libssl.a ${CURRENTPATH}/lib/ios/Openssl.framework/ssl
cp ${CURRENTPATH}/lib/ios/libssl.a ${CURRENTPATH}/lib/ios/Ssl.framework/ssl
cp ${CURRENTPATH}/lib/ios/libcrypto.a ${CURRENTPATH}/lib/ios/Openssl.framework/crypto
cp ${CURRENTPATH}/lib/ios/libcrypto.a ${CURRENTPATH}/lib/ios/Crypto.framework/crypto

echo "iOS Done."








echo "starting android build"

if [ ! -d "${ANDROID_NDK_HOME}" ]; then
  echo "ANDROID_NDK_HOME not defined or directory does not exist"
  exit 1
fi

echo "building android armv7"
echo "exporting android home and toolchain path"
export NDK=$ANDROID_NDK_HOME 
export TOOLCHAIN_PATH=${CURRENTPATH}/bin/android-toolchain-arm/bin 

if [ -d "${TOOLCHAIN_PATH}" ]; then
    echo "toolchain exists"
else
    echo "toolchain missing, creat it"
    $NDK/build/tools/make-standalone-toolchain.sh --platform=android-9 --toolchain=arm-linux-androideabi-4.6 --install-dir=${CURRENTPATH}/bin/android-toolchain-arm
fi

echo "exporting environment and compiler flags"

export TOOL=arm-linux-androideabi 
export NDK_TOOLCHAIN_BASENAME=${TOOLCHAIN_PATH}/${TOOL} 
export CC=$NDK_TOOLCHAIN_BASENAME-gcc 
export CXX=$NDK_TOOLCHAIN_BASENAME-g++ 
export LINK=${CXX} 
export LD=$NDK_TOOLCHAIN_BASENAME-ld 
export AR=$NDK_TOOLCHAIN_BASENAME-ar 
export RANLIB=$NDK_TOOLCHAIN_BASENAME-ranlib 
export STRIP=$NDK_TOOLCHAIN_BASENAME-strip 
export ARCH_FLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16" 
export ARCH_LINK="-march=armv7-a -Wl,--fix-cortex-a8" 
export CPPFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
export CXXFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -frtti -fexceptions " 
export CFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
export LDFLAGS=" ${ARCH_LINK} "

echo "configure openssl for armv7"

./Configure android-armv7

echo "building lib"

PATH=$TOOLCHAIN_PATH:$PATH make

echo "moving lib"
mv libcrypto.a ${CURRENTPATH}/lib/android/libs/armeabi-v7a/
mv libssl.a ${CURRENTPATH}/lib/android/libs/armeabi-v7a/




echo "building android arm"

export NDK=$ANDROID_NDK_HOME 
export TOOL=arm-linux-androideabi 
export NDK_TOOLCHAIN_BASENAME=${TOOLCHAIN_PATH}/${TOOL} 
export CC=$NDK_TOOLCHAIN_BASENAME-gcc 
export CXX=$NDK_TOOLCHAIN_BASENAME-g++ 
export LINK=${CXX} 
export LD=$NDK_TOOLCHAIN_BASENAME-ld 
export AR=$NDK_TOOLCHAIN_BASENAME-ar 
export RANLIB=$NDK_TOOLCHAIN_BASENAME-ranlib 
export STRIP=$NDK_TOOLCHAIN_BASENAME-strip 
export ARCH_FLAGS="-mthumb" 
export ARCH_LINK= 
export CPPFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
export CXXFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -frtti -fexceptions " 
export CFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 "
export LDFLAGS=" ${ARCH_LINK} " 


echo "configure openssl for arm"

./Configure android

echo "building lib"

PATH=$TOOLCHAIN_PATH:$PATH make

echo "moving lib"
mv libcrypto.a ${CURRENTPATH}/lib/android/libs/armeabi/
mv libssl.a ${CURRENTPATH}/lib/android/libs/armeabi/



echo "building android x86"
echo "exporting android home and toolchain path"
export NDK=$ANDROID_NDK_HOME 
export TOOLCHAIN_PATH=${CURRENTPATH}/bin/android-toolchain-x86/bin

if [ -d "${TOOLCHAIN_PATH}" ]; then
    echo "toolchain exists"
else
    echo "toolchain missing, creat it"
    $NDK/build/tools/make-standalone-toolchain.sh --platform=android-9 --toolchain=x86-4.6 --install-dir=${CURRENTPATH}/bin/android-toolchain-x86
fi

echo "exporting environment and compiler flags"

export TOOL=i686-linux-android 
export NDK_TOOLCHAIN_BASENAME=${TOOLCHAIN_PATH}/${TOOL} 
export CC=$NDK_TOOLCHAIN_BASENAME-gcc 
export CXX=$NDK_TOOLCHAIN_BASENAME-g++ 
export LINK=${CXX} 
export LD=$NDK_TOOLCHAIN_BASENAME-ld 
export AR=$NDK_TOOLCHAIN_BASENAME-ar 
export RANLIB=$NDK_TOOLCHAIN_BASENAME-ranlib 
export STRIP=$NDK_TOOLCHAIN_BASENAME-strip 
export ARCH_FLAGS="-march=i686 -msse3 -mstackrealign -mfpmath=sse" 
export ARCH_LINK=
export CPPFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
export CXXFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 -frtti -fexceptions " 
export CFLAGS=" ${ARCH_FLAGS} -fpic -ffunction-sections -funwind-tables -fstack-protector -fno-strict-aliasing -finline-limit=64 " 
export LDFLAGS=" ${ARCH_LINK} " 

echo "configure openssl for x86"

./Configure android-x86 

echo "building lib"

PATH=$TOOLCHAIN_PATH:$PATH make build_libs

echo "moving lib"

mv libcrypto.a ${CURRENTPATH}/lib/android/libs/x86/
mv libssl.a ${CURRENTPATH}/lib/android/libs/x86/

echo "cleanig up temp directory"
rm -rf "${CURRENTPATH}/src/openssl-${VERSION}"

echo "clear export flags"
export NDK=
export TOOL=
export NDK_TOOLCHAIN_BASENAME=
export CC=
export CXX=
export LINK=
export LD=
export AR=
export RANLIB=
export STRIP=
export ARCH_FLAGS=
export ARCH_LINK= 
export CPPFLAGS=
export CXXFLAGS= 
export CFLAGS=
export LDFLAGS=

echo "all done :)"
