# Summary

Have you ever wanted to program an OpenGL app on macOS? Would you like to do it **without 
XCode** or `.nib` files or storyboards? Would you like someone to present you with the **bare minimum
code** that you need to get started? If "YES!" is the answer to any of those questions, this repo is
for you!

Example code is provided for both legacy and core contexts. Note that the only real difference
between legacy and core contexts is:

```obj-c
  NSOpenGLPixelFormatAttribute Profile = NSOpenGLProfileVersionLegacy;
  // vs
  NSOpenGLPixelFormatAttribute Profile = NSOpenGLProfileVersion4_1Core;
```

and of course the loading of OpenGL extensions for the core context.

Note that this repo does not intend to give you a tutorial on OpenGL, it only aims to guide you
through **context creation** with only native APIs.

![Opengl triangle image](../media/Triangle.png?raw=true)

# Building and running

The shell script `build.sh` will build both the legacy and modern examples.

```bash
sh build.sh
build/legacy
build/modern
```
