#!/bin/sh

if [ ! -d build ]; then
  mkdir build
fi

pushd build > /dev/null

CommonCompilerFlags="
-g
-Wno-deprecated-declarations
-fdiagnostics-absolute-paths
-framework AppKit
-framework OpenGL
"

clang $CommonCompilerFlags ../src/main.m -o main

ErrorCode=$?

popd > /dev/null

exit $ErrorCode
