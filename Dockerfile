FROM ubuntu:20.04

#SDK TOOLS 26.1.1
ENV ANDROID_SDK_HOME="/usr/lib/android-sdk" \
    DEBIAN_FRONTEND="noninteractive"

#Cannot access environment variables in the same time they are defined
ENV PATH="$PATH:$ANDROID_SDK_HOME/tools:$ANDROID_SDK_HOME/tools/bin:$ANDROID_SDK_HOME/platform-tools:$ANDROID_SDK_HOME/cmdline-tools/latest/bin" \
    ANDROID_NDK_HOME="$ANDROID_SDK_HOME/ndk-current" \
    ANDROID_HOME="$ANDROID_SDK_HOME" \
    ANDROID_SDK_ROOT="$ANDROID_SDK_HOME"

#Base
# add java before maven to prevent downloading java 9
RUN apt-get update \
    && apt-get install -yq \
        build-essential \
        bash \
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
        openjdk-11-jre-headless \
        maven \
    && apt-get clean

##Android SDK
RUN echo "************ Installing Android Commandline Tools ************" \
    && wget --output-document=sdk-tools.zip -q \
        "https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip" \
    && mkdir -p "$ANDROID_SDK_HOME/cmdline-tools" \
   && unzip -q sdk-tools.zip -d "$ANDROID_SDK_HOME/cmdline-tools" \
   && mv "$ANDROID_SDK_HOME/cmdline-tools/cmdline-tools" "$ANDROID_SDK_HOME/cmdline-tools/latest" \
    && rm -f sdk-tools.zip

#The `yes` is for accepting all non-standard tool licenses.
RUN mkdir "$ANDROID_SDK_HOME/.android" \
    && touch "$ANDROID_SDK_HOME/.android/repositories.cfg"

RUN yes | sdkmanager --licenses

#Build Tools
RUN echo "************ Installing Platforms ************" \ 
    && sdkmanager "platforms;android-21" "platforms;android-23" "platforms;android-25"

RUN echo "************ Installing Platform Tools ************" \
    && sdkmanager 'platform-tools'

RUN echo "************ Installing Build Tools ************" \
    && sdkmanager 'build-tools;33.0.1'

# CMake
RUN echo "************ Installing C++ Support ************" \
    && sdkmanager 'cmake;3.22.1'

ENV NDK_VERSION=25b
# NDK
RUN echo "************ Installing Android NDK ${NDK_VERSION} ************" \
    && wget --output-document=$HOME/ndk.zip -q \
        "https://dl.google.com/android/repository/android-ndk-r${NDK_VERSION}-linux.zip" \
    && mkdir -p $ANDROID_NDK_HOME \
    && unzip -q $HOME/ndk.zip -d $ANDROID_NDK_HOME  \
    && mv $ANDROID_NDK_HOME/android-ndk-r${NDK_VERSION}/* $ANDROID_NDK_HOME \
    && rm -f $HOME/ndk.zip && rm -d $ANDROID_NDK_HOME/android-ndk-r${NDK_VERSION}

RUN useradd build -m -u 112
USER build

RUN mkdir -p /home/build/.m2 && mkdir -p /home/build/app
COPY . /home/build/app/

WORKDIR /home/build/app/
