#!/bin/sh

[ -d build ] || mkdir build
cd build

CompilerFlags="
-Wno-deprecated-declarations
-fdiagnostics-absolute-paths
-framework AppKit
-framework OpenGL
"

clang $CompilerFlags ../src/modern.m -o modern
clang $CompilerFlags ../src/legacy.m -o legacy

ErrorCode=$?

exit $ErrorCode
