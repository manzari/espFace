# Flutter + Android SDK image for apps/mobile (CI and local builds). Mirrors the local inhumane-flutter:latest
# (Flutter 3.44.0, platform 36, build-tools 36.0.0, Java 21, ANDROID_HOME=/opt/android-sdk-linux, workdir /workspace).
FROM eclipse-temurin:21-jdk-jammy

ARG FLUTTER_VERSION=3.44.0
ARG CMDLINE_TOOLS=13114758
ENV ANDROID_HOME=/opt/android-sdk-linux \
    ANDROID_SDK_ROOT=/opt/android-sdk-linux \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    PATH=/opt/flutter/bin:/opt/android-sdk-linux/cmdline-tools/latest/bin:/opt/android-sdk-linux/platform-tools:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils zip ca-certificates libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL -o /tmp/ct.zip https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip \
    && unzip -q /tmp/ct.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/ct.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && git config --global --add safe.directory ${FLUTTER_HOME} \
    && flutter config --no-analytics --enable-android \
    && flutter precache --android \
    && flutter doctor

WORKDIR /workspace
