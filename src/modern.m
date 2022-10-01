/*
 * Creates a native window with a valid OpenGL rendering context and draws a 2D triangle.
 *
 * Compile with: clang -Wno-deprecated-declarations -framework AppKit -framework OpenGL modern.m
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
#include <dlfcn.h> // NOTE(robin): For loading OpenGL extensions

int Running = 1;
int NeedsResize = 1; // NOTE(robin): Initially, OpenGL doesn't know how large the viewport is
                     // so we need to tell it when we start up.

// NOTE(robin): These two functions are not provided in the Apple OpenGL header
// so we need to define them here and load them at runtime
typedef void glBindVertexArrayFn(GLuint id);
typedef void glGenVertexArraysFn(GLsizei n, GLuint *ids);
glBindVertexArrayFn* glBindVertexArray;
glGenVertexArraysFn* glGenVertexArrays;

GLint GlobalShaderProgram;

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

  typedef struct
  {
    float x, y, z;
    float r, g, b, a;
  } vertex;

  vertex Vertices[] =
  {
    // Position           Colour
    { -.5f, -.5f, 0.0f,   1.0f, 0.0f, 0.0f, 1.0f },
    { 0.5f, -.5f, 0.0f,   0.0f, 1.0f, 0.0f, 1.0f },
    { 0.0f, 0.5f, 0.0f,   0.0f, 0.0f, 1.0f, 1.0f },
  };

  GLuint VBO, VAO;
  glGenBuffers(1, &VBO);
  glBindBuffer(GL_ARRAY_BUFFER, VBO);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);

  glGenVertexArrays(1, &VAO);
  glBindVertexArray(VAO);
  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(vertex), (void*)offsetof(vertex, x));
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(vertex), (void*)offsetof(vertex, r));

  glUseProgram(GlobalShaderProgram);

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

    glDrawArrays(GL_TRIANGLES, 0, 3);

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
  [NSApp activateIgnoringOtherApps:YES];
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
  NSOpenGLPixelFormatAttribute Profile = NSOpenGLProfileVersion4_1Core;

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

  // =====================Compile our shader=====================

  GLint VertexShader = glCreateShader(GL_VERTEX_SHADER);
  GLint FragmentShader = glCreateShader(GL_FRAGMENT_SHADER);

  GlobalShaderProgram = glCreateProgram();

  const char* VertexShaderSource =
    "#version 330 core\n"
    "layout (location = 0) in vec3 aPosition;"
    "layout (location = 1) in vec4 aColour;"
    "out vec4 Colour;"
    "void main(void)"
    "{"
    "  gl_Position = vec4(aPosition, 1.0);"
    "  Colour = aColour;"
    "}"
    ;

  const char* FragmentShaderSource =
    "#version 330 core\n"
    "in vec4 Colour;"
    "out vec4 Fragment;"
    "void main(void)"
    "{"
    "  Fragment = Colour;"
    "}"
    ;

  glShaderSource(VertexShader, 1, &VertexShaderSource, 0);
  glShaderSource(FragmentShader, 1, &FragmentShaderSource, 0);

  char Log[512] = {0};

  glCompileShader(VertexShader);
  glCompileShader(FragmentShader);

  glGetShaderInfoLog(VertexShader, sizeof(Log), 0, Log); printf("%s", Log);
  glGetShaderInfoLog(FragmentShader, sizeof(Log), 0, Log); printf("%s", Log);

  glAttachShader(GlobalShaderProgram, VertexShader);
  glAttachShader(GlobalShaderProgram, FragmentShader);

  glLinkProgram(GlobalShaderProgram);
  glGetProgramInfoLog(GlobalShaderProgram, sizeof(Log), 0, Log); printf("%s", Log);

  // ===============Load OpenGL Extension Pointers===============

  const char* PossiblePaths[] = {
    "../Frameworks/OpenGL.framework/OpenGL",
    "/Library/Frameworks/OpenGL.framework/OpenGL",
    "/System/Library/Frameworks/OpenGL.framework/OpenGL",
    "/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL"
  };

  void* LibGL = 0;

  for (int i = 0; i < sizeof(PossiblePaths) / sizeof(PossiblePaths[0]); i++)
  {
    LibGL = dlopen(PossiblePaths[i], RTLD_LAZY | RTLD_LOCAL);
    if (LibGL)
      break;
  }

  glGenVertexArrays = (glGenVertexArraysFn*)dlsym(LibGL, "glGenVertexArrays");
  glBindVertexArray = (glBindVertexArrayFn*)dlsym(LibGL, "glBindVertexArray");

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
