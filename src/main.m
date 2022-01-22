#define GL_SILENCE_DEPRECATION

#include <AppKit/AppKit.h>
#include <OpenGL/gl.h>

NSOpenGLContext* GLContext;
int Running = 1;

@interface AppDelegate : NSObject<NSApplicationDelegate, NSWindowDelegate>
@end

@implementation AppDelegate
- (void)windowDidResize:(NSNotification*)notification
{
  NSWindow* Window = [notification object];
  NSRect Frame = [Window contentView].bounds;

  // NOTE(robin): This assumes retina scaling at 200%. For proper code you would
  // want to query what the current display scaling is set to.
  float Scale = 2;

  glLoadIdentity();
  glViewport(0, 0, Frame.size.width*Scale, Frame.size.height*Scale);

  [GLContext update];
}

- (void)windowWillClose:(id)sender
{
  Running = 0;
}
@end

int main(void)
{
  NSApplication* App = [NSApplication sharedApplication];
  [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

  AppDelegate* MainAppDelegate = [[AppDelegate alloc] init];
  [App setDelegate: MainAppDelegate];
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
  [GLContext makeCurrentContext];

  while (Running)
  {
    NSEvent* Event;

    // NOTE(robin): You probably want to handle the message queue and rendering
    // commands in separate threads. This is just shown here for simplicity.
    do
    {
      Event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                 untilDate: nil
                                    inMode: NSDefaultRunLoopMode
                                   dequeue: true];

      switch ([Event type])
      {
        default:
          [NSApp sendEvent: Event];
      }


    } while (Event);

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

  return 0;
}
