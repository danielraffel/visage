/* Copyright Vital Audio, LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#if VISAGE_IOS
#include "windowing_ios.h"

#include "visage_utils/time_utils.h"

namespace visage {
  class InitialMetalLayer {
  public:
    static CAMetalLayer* layer() { return instance().metal_layer_; }

  private:
    static InitialMetalLayer& instance() {
      static InitialMetalLayer instance;
      return instance;
    }

    InitialMetalLayer() {
      metal_layer_ = [CAMetalLayer layer];
      metal_layer_.device = MTLCreateSystemDefaultDevice();
      metal_layer_.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    }

    CAMetalLayer* metal_layer_ = nullptr;
  };
}

// =============================================================================
// VisageMetalViewDelegate — drives the render loop
// =============================================================================

@implementation VisageMetalViewDelegate

- (instancetype)initWithWindow:(visage::WindowIos*)window {
  self = [super init];
  self.visage_window = window;
  self.start_microseconds = visage::time::microseconds();
  return self;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  self.visage_window->handleNativeResize(size.width, size.height);
}

- (void)drawInMTKView:(MTKView*)view {
  if (!view.currentDrawable || !view.currentRenderPassDescriptor)
    return;

  view.layer.contentsScale = self.visage_window->dpiScale();
  long long ms = visage::time::microseconds();
  self.visage_window->drawCallback((ms - self.start_microseconds) / 1000000.0);
}

@end

// =============================================================================
// VisageMetalView — MTKView subclass with touch event handling
// =============================================================================

@implementation VisageMetalView

- (instancetype)initWithFrame:(CGRect)frame inWindow:(visage::WindowIos*)window {
  self = [super initWithFrame:frame];
  self.visage_window = window;
  self.device = MTLCreateSystemDefaultDevice();
  self.clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);
  self.enableSetNeedsDisplay = NO;
  self.framebufferOnly = YES;
  self.preferredFramesPerSecond = 60;
  self.multipleTouchEnabled = NO;
  self.active_touch = nil;
  return self;
}

// ---------------------------------------------------------------------------
// Touch → mouse event mapping
//
// Visage's event system is mouse-oriented. We map a single primary touch to
// left-button mouse events. Coordinates are in UIView space (top-left origin,
// points) scaled by dpiScale() to native pixels — same coordinate system
// Visage uses internally.
// ---------------------------------------------------------------------------

- (visage::Point)touchPosition:(UITouch*)touch {
  CGPoint location = [touch locationInView:self];
  float scale = self.visage_window->dpiScale();
  return visage::Point(location.x * scale, location.y * scale);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if (self.active_touch != nil)
    return;

  UITouch* touch = [touches anyObject];
  self.active_touch = touch;

  visage::Point point = [self touchPosition:touch];
  self.visage_window->handleMouseDown(visage::kMouseButtonLeft, point.x, point.y,
                                      visage::kMouseButtonLeft, 0);
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if (self.active_touch == nil || ![touches containsObject:self.active_touch])
    return;

  visage::Point point = [self touchPosition:self.active_touch];
  self.visage_window->handleMouseMove(point.x, point.y, visage::kMouseButtonLeft, 0);
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if (self.active_touch == nil || ![touches containsObject:self.active_touch])
    return;

  visage::Point point = [self touchPosition:self.active_touch];
  self.visage_window->handleMouseUp(visage::kMouseButtonLeft, point.x, point.y, 0, 0);
  self.active_touch = nil;
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if (self.active_touch == nil)
    return;

  visage::Point point = [self touchPosition:self.active_touch];
  self.visage_window->handleMouseUp(visage::kMouseButtonLeft, point.x, point.y, 0, 0);
  self.active_touch = nil;
}

@end

// =============================================================================
// WindowIos implementation
// =============================================================================

namespace visage {

  WindowIos::WindowIos(int width, int height, float scale)
      : Window(width, height) {
    setDpiScale(scale);
    CGRect frame = CGRectMake(0.0f, 0.0f, width / scale, height / scale);
    view_ = [[VisageMetalView alloc] initWithFrame:frame inWindow:this];
    view_delegate_ = [[VisageMetalViewDelegate alloc] initWithWindow:this];
    view_.delegate = view_delegate_;
  }

  WindowIos::WindowIos(int width, int height, float scale, void* parent_handle)
      : Window(width, height) {
    setDpiScale(scale);
    parent_view_ = (__bridge UIView*)parent_handle;
    CGRect frame = CGRectMake(0.0f, 0.0f, width / scale, height / scale);
    view_ = [[VisageMetalView alloc] initWithFrame:frame inWindow:this];
    view_delegate_ = [[VisageMetalViewDelegate alloc] initWithWindow:this];
    view_.delegate = view_delegate_;

    if (parent_view_)
      [parent_view_ addSubview:view_];
  }

  WindowIos::~WindowIos() {
    view_.visage_window = nullptr;
    if (parent_view_)
      [view_ removeFromSuperview];
  }

  void WindowIos::runEventLoop() {
    [[NSRunLoop mainRunLoop] run];
  }

  void* WindowIos::initWindow() const {
    return (__bridge void*)InitialMetalLayer::layer();
  }

  void WindowIos::windowContentsResized(int width, int height) {
    float scale = dpiScale();
    [view_ setFrame:CGRectMake(0.0f, 0.0f, width / scale, height / scale)];
  }

  void WindowIos::show() {
    view_.hidden = NO;
    handleWindowShown();
  }

  void WindowIos::showMaximized() {
    show();
  }

  void WindowIos::hide() {
    view_.hidden = YES;
    handleWindowHidden();
  }

  void WindowIos::close() {
    hide();
    [view_ removeFromSuperview];
  }

  bool WindowIos::isShowing() const {
    return view_ != nil && !view_.hidden;
  }

  void WindowIos::setWindowTitle(const std::string& title) {
    // No window chrome on iOS
  }

  IPoint WindowIos::maxWindowDimensions() const {
    CGRect screen = [[UIScreen mainScreen] bounds];
    float scale = [[UIScreen mainScreen] nativeScale];
    return { static_cast<int>(screen.size.width * scale),
             static_cast<int>(screen.size.height * scale) };
  }

  void WindowIos::handleNativeResize(int width, int height) {
    handleResized(width, height);
  }

  // ---------------------------------------------------------------------------
  // Factory functions
  // ---------------------------------------------------------------------------

  std::unique_ptr<Window> createWindow(const Dimension& x, const Dimension& y,
                                       const Dimension& width, const Dimension& height,
                                       Window::Decoration decoration_style) {
    float scale = defaultDpiScale();
    IBounds bounds = computeWindowBounds(x, y, width, height);
    return std::make_unique<WindowIos>(bounds.width(), bounds.height(), scale);
  }

  std::unique_ptr<Window> createPluginWindow(const Dimension& width, const Dimension& height,
                                             void* parent_handle) {
    float scale = defaultDpiScale();
    CGRect screen = [[UIScreen mainScreen] bounds];
    int screen_width = static_cast<int>(screen.size.width * scale);
    int screen_height = static_cast<int>(screen.size.height * scale);
    int w = width.computeInt(scale, screen_width, screen_height);
    int h = height.computeInt(scale, screen_width, screen_height);
    return std::make_unique<WindowIos>(w, h, scale, parent_handle);
  }

  // ---------------------------------------------------------------------------
  // Global utility functions
  // ---------------------------------------------------------------------------

  bool isMobileDevice() { return true; }

  float defaultDpiScale() {
    return static_cast<float>([[UIScreen mainScreen] nativeScale]);
  }

  IBounds computeWindowBounds(const Dimension& x, const Dimension& y,
                              const Dimension& width, const Dimension& height) {
    float scale = defaultDpiScale();
    CGRect screen = [[UIScreen mainScreen] bounds];
    int screen_width = static_cast<int>(screen.size.width * scale);
    int screen_height = static_cast<int>(screen.size.height * scale);

    int w = width.computeInt(scale, screen_width, screen_height);
    int h = height.computeInt(scale, screen_width, screen_height);
    int px = x.computeInt(scale, screen_width, screen_height);
    int py = y.computeInt(scale, screen_width, screen_height);
    return { px, py, px + w, py + h };
  }

  void setCursorStyle(MouseCursor style) { }
  void setCursorVisible(bool visible) { }

  Point cursorPosition() { return { 0.0f, 0.0f }; }
  void setCursorPosition(Point window_position) { }
  void setCursorScreenPosition(Point screen_position) { }

  void showMessageBox(std::string title, std::string message) {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIAlertController* alert =
          [UIAlertController alertControllerWithTitle:[NSString stringWithUTF8String:title.c_str()]
                                             message:[NSString stringWithUTF8String:message.c_str()]
                                      preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
      UIViewController* root =
          [UIApplication sharedApplication].keyWindow.rootViewController;
      if (root)
        [root presentViewController:alert animated:YES completion:nil];
    });
  }

  std::string readClipboardText() {
    UIPasteboard* pb = [UIPasteboard generalPasteboard];
    return pb.string ? std::string([pb.string UTF8String]) : std::string();
  }

  void setClipboardText(const std::string& text) {
    [UIPasteboard generalPasteboard].string =
        [NSString stringWithUTF8String:text.c_str()];
  }

  void closeApplication() { }
}

#endif
