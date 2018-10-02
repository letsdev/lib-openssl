FROM ubuntu:bionic-20180224

#SDK TOOLS 26.1.1
ENV ANDROID_SDK_HOME="/opt/android-sdk" \
    ANDROID_SDK_TOOLS_VERSION="4333796" \
    DEBIAN_FRONTEND="noninteractive"

#Cannot access environment variables in the same time they are defined
ENV PATH="$PATH:$ANDROID_SDK_HOME/tools:$ANDROID_SDK_HOME/tools/bin:$ANDROID_SDK_HOME/platform-tools" \
    ANDROID_NDK_HOME="$ANDROID_SDK_HOME/ndk-bundle" \
    ANDROID_HOME="$ANDROID_SDK_HOME" \
    ANDROID_SDK_ROOT="$ANDROID_SDK_HOME"

#Base
# add java before maven to prevent downloading java 9
RUN apt-get update \
    && apt-get install -yq \
        build-essential \
        software-properties-common \
        git \
        ninja-build \
        cmake \
        python \
        wget \ 
        unzip \
        zip \
        clang \
        systemtap-sdt-dev \
        libbsd-dev \
        linux-libc-dev \
        openjdk-8-jre-headless \
        maven \
    && apt-get clean

#Android SDK
RUN echo "************ Installing Android SDK Tools ************" \
    && wget --output-document=sdk-tools.zip -q \
        "https://dl.google.com/android/repository/sdk-tools-linux-$ANDROID_SDK_TOOLS_VERSION.zip" \
    && mkdir -p "$ANDROID_SDK_HOME" \
    && unzip -q sdk-tools.zip -d "$ANDROID_SDK_HOME" \
    && rm -f sdk-tools.zip

#The `yes` is for accepting all non-standard tool licenses.
RUN mkdir "$ANDROID_SDK_HOME/.android" \
    && touch "$ANDROID_SDK_HOME/.android/repositories.cfg"

RUN yes | sdkmanager --licenses

#Build Tools
RUN echo "************ Installing Build Tools ************" \
    && sdkmanager 'build-tools;28.0.3'

# CMake
RUN echo "************ Installing C++ Support ************" \
    && sdkmanager 'cmake;3.6.4111459' 

# NDK
RUN echo "************ Installing Android NDK 17c ************" \
    && wget --output-document=$HOME/ndk.zip -q \
        "https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip" \
    && mkdir -p $ANDROID_NDK_HOME \
    && unzip -q $HOME/ndk.zip -d $ANDROID_NDK_HOME  \
    && mv $ANDROID_NDK_HOME/android-ndk-r17c/* $ANDROID_NDK_HOME \
    && rm -f $HOME/ndk.zip && rm -d $ANDROID_NDK_HOME/android-ndk-r17c

RUN useradd build -m -u 112
USER build

RUN mkdir -p /home/build/.m2 && mkdir -p /home/build/app
COPY . /home/build/app/

WORKDIR /home/build/app/
