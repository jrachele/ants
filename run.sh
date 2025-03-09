mkdir -p build

odin build src/ -debug -out=./build/ants

./build/ants
