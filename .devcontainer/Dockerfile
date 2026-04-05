FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install system dependencies for Flutter
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    openjdk-17-jdk \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME (architecture-independent via symlink)
RUN ln -s /usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture) /usr/lib/jvm/java-17-openjdk
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk

# Install Flutter SDK as vscode user
USER vscode
WORKDIR /home/vscode

# Download and install Flutter (latest stable)
RUN git clone https://github.com/flutter/flutter.git -b stable --depth 1 /home/vscode/flutter

# Add Flutter to PATH
ENV PATH="/home/vscode/flutter/bin:${PATH}"

# Pre-download Flutter dependencies
RUN flutter precache --web

# Accept licenses
RUN yes | flutter doctor --android-licenses || true

USER root
