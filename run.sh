#!/bin/bash

# Default build mode is debug
BUILD_MODE="debug"

# Parse command-line arguments
if [[ "$1" == "release" ]]; then
  BUILD_MODE="release"
elif [[ "$1" == "debug" ]]; then
  BUILD_MODE="debug"
else
  echo "Usage: $0 [debug|release]"
  exit 1
fi

# Create build directory
mkdir -p build

# Build based on the selected mode
if [[ "$BUILD_MODE" == "debug" ]]; then
  echo "Building in debug mode..."
  odin build src/ -debug -out=./build/ants
elif [[ "$BUILD_MODE" == "release" ]]; then
  echo "Building in release mode with optimizations..."
  odin build src/ -o:speed -out=./build/ants
fi

# Run the compiled program
if [[ $? -eq 0 ]]; then
  echo "Running the program..."
  ./build/ants
else
  echo "Build failed."
  exit 1
fi
