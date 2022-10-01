/*
 * Creates a native window with a valid OpenGL rendering context and draws a 2D triangle.
 *
 * Compile with: clang -Wno-deprecated-declarations -framework AppKit -framework OpenGL legacy.m
 *
 * Author: Robin Leathart
 *
 * ====================Notes on macOS OpenGL====================
 *
 * OpenGL is technically deprecated on macOS in favour of Metal, Apple's proprietary low-level
 * graphics API. This means that while OpenGL apps will continue to run (for now), the version of
 * OpenGL is stuck at 4.1 and will never be updated. Apple also offers no compatibility contexts
 * which means you must choose either the legacy fixed-function pipeline, or the modern
 * shader-based programmable pipeline (OpenGL 'Core'). You cannot use both at the same time.
 *
 * There are differences between the structure of a Windows or Linux OpenGL program and a macOS
 * OpenGL program. Most notably, you cannot block the main thread on macOS because only the main
 * thread is permitted to receive events and update the UI. This means we have to have at least 2
 * threads. One is the main thread that receives and responds to events, the other is a thread for
 * running our OpenGL render loop: the 'RenderThread' in this example. This is different to a
 * Windows or Linux application where you can handle event processing and rendering in the same
 * thread.
 *
 * Finally, many events that are handled in a message loop on Windows or Linux, e.g. window resizing,
 * are handled instead by delegate callbacks. For example the windowDidResize method in our
 * WindowDelegate.
 *
 * =============================================================
 *
 */

#define GL_SILENCE_DEPRECATION

#include <AppKit/AppKit.h>
#include <OpenGL/gl.h>

int Running = 1;
int NeedsResize = 1; // NOTE(robin): Initially, OpenGL doesn't know how large the viewport is
                     // so we need to tell it when we start up.

// NOTE(robin): We need a very simple delegate here to allow us
// to access information about when the window is closed or resized.
@interface WindowDelegate : NSObject<NSWindowDelegate>
@end

@implementation WindowDelegate

- (void)windowDidResize:(NSNotification *) notification
{
  NeedsResize = 1;
}

- (void)windowWillClose:(id)sender
{
  Running = 0;
}
@end

void RenderThread(NSOpenGLContext* GLContext, NSWindow* Window)
{
  [GLContext makeCurrentContext];

  while (Running)
  {
    if (NeedsResize)
    {
      NSRect Frame = [Window contentView].bounds;
      double Scale = [[Window screen] backingScaleFactor];

      glViewport(0, 0, Frame.size.width * Scale, Frame.size.height * Scale);

      // NOTE(robin): update has to be called on the main thread so we dispatch it here. This will
      // block until [GLContext update] has completed execution on the main thread.
      [GLContext performSelectorOnMainThread:@selector(update)
                                  withObject:nil
                               waitUntilDone:YES];
      NeedsResize = 0;
    }

    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);

    glBegin(GL_TRIANGLES);
    {
      glColor3f(1, 0, 0); glVertex2f(-.5, -.5);
      glColor3f(0, 1, 0); glVertex2f(0.5, -.5);
      glColor3f(0, 0, 1); glVertex2f(0.0, 0.5);
    }
    glEnd();

    // NOTE(robin): This is the primary reason that we require a separate thread for the rendering.
    // Calling flushBuffer will block, so we cannot call it in the main thread.
    [GLContext flushBuffer]; // NOTE(robin): Swap the backbuffer
  }
}

int main(void)
{
  // =======================Window Creation=======================

  NSApplication* App = [NSApplication sharedApplication];
  [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
  [NSApp finishLaunching];

  NSRect Frame = NSMakeRect(0, 0, 1024, 768);
  NSWindow* Window = [[NSWindow alloc] initWithContentRect:Frame
                                                 styleMask:NSWindowStyleMaskTitled
                                                 | NSWindowStyleMaskClosable
                                                 | NSWindowStyleMaskMiniaturizable
                                                 | NSWindowStyleMaskResizable
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];

  [Window makeKeyAndOrderFront:nil];
  [Window setDelegate:[[WindowDelegate alloc] init]];
  [Window center];

  // ===================OpenGL Context Creation===================

  // NOTE(robin): Choose a legacy profile if you want to use the fixed function pipeline.
  // Otherwise choose a modern profile to get a context that is compatible with the
  // modern shader based pipeline. Possible options are:
  //
  // NSOpenGLProfileVersionLegacy
  // NSOpenGLProfileVersion3_2Core
  // NSOpenGLProfileVersion4_1Core
  //
  NSOpenGLPixelFormatAttribute Profile = NSOpenGLProfileVersionLegacy;

  NSOpenGLPixelFormatAttribute Attributes[] =
  {
    NSOpenGLPFAAccelerated,
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAOpenGLProfile,
    Profile,
    0
  };

  NSOpenGLPixelFormat* Format = [[NSOpenGLPixelFormat alloc] initWithAttributes:Attributes];
  NSOpenGLContext* GLContext = [[NSOpenGLContext alloc] initWithFormat:Format shareContext:nil];
  [Format release];

  int SwapMode = 1; // NOTE(robin): Enable VSync
  [GLContext setValues:&SwapMode forParameter:NSOpenGLContextParameterSwapInterval];
  [GLContext setView:[Window contentView]]; // NOTE(robin): Associate the context with our window
  [GLContext makeCurrentContext];

  // =================We now have a valid context================

  printf("OpenGL Renderer: %s\n", glGetString(GL_RENDERER));
  printf("OpenGL Version: %s\n", glGetString(GL_VERSION));

  // =========================Event loop=========================

  // NOTE(robin): On macOS only the main thread is permitted to update the UI and
  // receive events. Because of this, we reserve the main thread for event processing
  // and create a new thread to execute our opengl commands.
  [[[NSThread alloc] initWithBlock: ^{RenderThread(GLContext, Window);}] start];

  while (Running)
  {
    NSEvent* Event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                        untilDate: [NSDate distantFuture] // NOTE(robin): Block until next event
                                           inMode: NSDefaultRunLoopMode
                                          dequeue: YES];

    // NOTE(robin): Process each event here however you like

    [NSApp sendEvent: Event];
    [NSApp updateWindows];
  }

  return 0;
}
