#define GL_SILENCE_DEPRECATION

#include <AppKit/AppKit.h>
#include <OpenGL/gl.h>
#include <dlfcn.h>

NSOpenGLContext* GLContext;
int Running = 1;
int NeedsResize = 1;

GLint GlobalShaderProgram;

// NOTE(robin): These two functions are not provided in the Apple OpenGL header
// so we need to define them here and load them at runtime
typedef void glBindVertexArrayFn(GLuint id);
typedef void glGenVertexArraysFn(GLsizei n, GLuint *ids);
glBindVertexArrayFn* glBindVertexArray;
glGenVertexArraysFn* glGenVertexArrays;

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

      // NOTE(robin): update has to be called on the main thread so we dispatch it here
      [GLContext performSelectorOnMainThread:@selector(update)
                                  withObject:nil
                               waitUntilDone:YES];
      NeedsResize = 0;
    }

    glDrawArrays(GL_TRIANGLES, 0, 3);

    [GLContext flushBuffer]; // NOTE(robin): Swap the backbuffer
  }
}

int main(void)
{
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

  NSOpenGLPixelFormatAttribute Attributes[] =
  {
    NSOpenGLPFAAccelerated,
    NSOpenGLPFADoubleBuffer,

    // NOTE(robin): Choose a legacy profile if you want to use the fixed function pipeline.
    // Otherwise choose a modern profile to get a context that is compatible with the
    // modern shader based pipeline.
    NSOpenGLPFAOpenGLProfile,
    // NSOpenGLProfileVersionLegacy,
    // NSOpenGLProfileVersion3_2Core,
    NSOpenGLProfileVersion4_1Core,
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

  glCompileShader(VertexShader);
  glCompileShader(FragmentShader);

  char Log[512] = {0};

  glGetShaderInfoLog(VertexShader, sizeof(Log), 0, Log); printf("%s", Log);
  glGetShaderInfoLog(FragmentShader, sizeof(Log), 0, Log); printf("%s", Log);

  glAttachShader(GlobalShaderProgram, VertexShader);
  glAttachShader(GlobalShaderProgram, FragmentShader);

  glLinkProgram(GlobalShaderProgram);
  glGetProgramInfoLog(GlobalShaderProgram, sizeof(Log), 0, Log); printf("%s", Log);

  // ==========Load OpenGL Extension Pointers==========

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

  glGenVertexArrays = dlsym(LibGL, "glGenVertexArrays");
  glBindVertexArray = dlsym(LibGL, "glBindVertexArray");

  // ==================================================

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
