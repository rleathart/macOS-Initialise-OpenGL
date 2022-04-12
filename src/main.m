#define GL_SILENCE_DEPRECATION

#include <AppKit/AppKit.h>
#include <OpenGL/gl.h>

NSOpenGLContext* GLContext;
int Running = 1;
int WindowIsResizing;

@interface AppDelegate : NSObject<NSApplicationDelegate, NSWindowDelegate>
@end

@implementation AppDelegate
- (void)windowDidResize:(NSNotification*)notification
{
  WindowIsResizing = 1;
  NSWindow* Window = [notification object];
  NSRect Frame = [Window contentView].bounds;

  // NOTE(robin): This assumes retina scaling at 200%. For proper code you would
  // want to query what the current display scaling is set to.
  float Scale = 2;

  glLoadIdentity();
  glViewport(0, 0, Frame.size.width*Scale, Frame.size.height*Scale);

  [GLContext update];
  WindowIsResizing = 0;
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
    if (WindowIsResizing)
      continue;

    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);

    glBegin(GL_TRIANGLES);
    {
      glColor3f(1, 0, 0); glVertex2f(-0.5, -0.5);
      glColor3f(0, 1, 0); glVertex2f(0, 0.5);
      glColor3f(0, 0, 1); glVertex2f(0.5, -0.5);
    }
    glEnd();

    [GLContext flushBuffer]; // NOTE(robin): Swap the backbuffer
  }
}

int main(void)
{
  NSApplication* App = [NSApplication sharedApplication];
  [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

  AppDelegate* MainAppDelegate = [[AppDelegate alloc] init];
  [App setDelegate:MainAppDelegate];
  [NSApp finishLaunching];

  NSRect ScreenRect = [[NSScreen mainScreen] frame];
  NSRect Frame = NSMakeRect(0, 0, 1024, 768);
  NSWindow* Window = [[NSWindow alloc] initWithContentRect:Frame
                                                 styleMask:NSWindowStyleMaskTitled
                                                 | NSWindowStyleMaskClosable
                                                 | NSWindowStyleMaskMiniaturizable
                                                 | NSWindowStyleMaskResizable
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];

  [Window makeKeyAndOrderFront:nil];
  [Window setDelegate:MainAppDelegate];
  [Window center];

  NSOpenGLPixelFormatAttribute Attributes[] =
  {
    NSOpenGLPFAAccelerated,
    NSOpenGLPFADoubleBuffer,
    0
  };

  NSOpenGLPixelFormat* Format = [[NSOpenGLPixelFormat alloc] initWithAttributes:Attributes];
  GLContext = [[NSOpenGLContext alloc] initWithFormat:Format shareContext:NULL];
  [Format release];

  int SwapMode = 1;
  [GLContext setValues:&SwapMode forParameter:NSOpenGLContextParameterSwapInterval];
  [GLContext setView:[Window contentView]];

  // NOTE(robin): We need to have our OpenGL commands execute in a separate thread
  // so that the main thread is free to process our event loop. Otherwise window
  // dragging (and probably other things) are delayed.
  [[[NSThread alloc] initWithBlock: ^{RenderThread(GLContext, Window);}] start];

  while (Running)
  {
    NSEvent* Event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                        untilDate: [NSDate distantFuture]
                                           inMode: NSDefaultRunLoopMode
                                          dequeue: YES];

    // NOTE(robin): Process each event here however you like

    [NSApp sendEvent: Event];
    [NSApp updateWindows];
  }

  return 0;
}
