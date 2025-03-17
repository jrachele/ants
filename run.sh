#!/bin/bash

# Default build mode is debug
BUILD_MODE="debug"

# Parse command-line arguments
if [[ "$1" == "release" ]]; then
  BUILD_MODE="release"
elif [[ "$1" == "debug" ]]; then
  BUILD_MODE="debug"
elif [[ "$1" == "test" ]]; then
  BUILD_MODE="test"
else
  echo "Usage: $0 [debug|release|test]"
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
elif [[ "$BUILD_MODE" == "test" ]]; then
  echo "Building in test mode..."
  odin build src/ -debug -build-mode:test -out=./build/ants_test
fi

# Run the compiled program
if [ $? -ne 0 ]; then
  echo "Build failed."
  exit 1
else
  echo "Build succeeded."
fi

if [ "$2" == "run" ]; then 
  echo "Running the program..."
  if [[ "$BUILD_MODE" == "test" ]]; then
    ./build/ants_test
  else 
    ./build/ants
  fi
fi