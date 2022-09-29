# Summary

Have you ever wanted to program an OpenGL app on macOS? Would you like to do it **without 
XCode** or `.nib` files or storyboards? Would you like someone to present you with the **bare minimum
code** that you need to get started? If "YES!" is the answer to any of those questions, this repo is
for you!

I wasn't able to find any guides that showed the bare minimum necessary to
create an OpenGL window using only native APIs. This repository is providing
just that!

Note that this repo does not intend to give you a tutorial on OpenGL, it only aims to guide you
through **native context creation**.

![Opengl triangle image](../media/Triangle.png?raw=true)

# Building and running

The shell script `build.sh` will build both the legacy and modern examples.

```bash
sh build.sh
build/legacy
build/modern
```
