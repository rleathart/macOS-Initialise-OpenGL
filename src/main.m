#define GL_SILENCE_DEPRECATION

#include <AppKit/AppKit.h>
#include <OpenGL/gl.h>

NSOpenGLContext* GLContext;
int Running = 1;
int NeedsResize = 0;

@interface AppDelegate : NSObject<NSApplicationDelegate, NSWindowDelegate>
@end

@implementation AppDelegate

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

      glLoadIdentity();
      glViewport(0, 0, Frame.size.width * Scale, Frame.size.height * Scale);

      // NOTE(robin): update has to be called on the main thread so we dispatch it here
      [GLContext performSelectorOnMainThread:@selector(update)
                                  withObject:nil
                               waitUntilDone:YES];
      NeedsResize = 0;
    }

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

    // NOTE(robin): Choose a legacy profile if you want to use the fixed function pipeline.
    // Otherwise choose a modern profile to get a context that is compatible with the
    // modern shader based pipeline.
    NSOpenGLPFAOpenGLProfile,
    NSOpenGLProfileVersionLegacy,
    // NSOpenGLProfileVersion3_2Core,
    // NSOpenGLProfileVersion4_1Core,
    0
  };

  NSOpenGLPixelFormat* Format = [[NSOpenGLPixelFormat alloc] initWithAttributes:Attributes];
  GLContext = [[NSOpenGLContext alloc] initWithFormat:Format shareContext:NULL];
  [Format release];

  int SwapMode = 1;
  [GLContext setValues:&SwapMode forParameter:NSOpenGLContextParameterSwapInterval];
  [GLContext setView:[Window contentView]];
  [GLContext makeCurrentContext];

  printf("OpenGL Renderer: %s\n", glGetString(GL_RENDERER));
  printf("OpenGL Version: %s\n", glGetString(GL_VERSION));

  // NOTE(robin): On macOS only the main thread is permitted to update the UI and
  // receive events. Because of this, we reserve the main thread for event processing
  // and create a new thread to execute our opengl commands.
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
