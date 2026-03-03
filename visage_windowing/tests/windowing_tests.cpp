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

#include "visage_windowing/windowing.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

using namespace visage;

TEST_CASE("Window base class default state", "[windowing]") {
  SECTION("Double click speed can be set and retrieved") {
    int original = Window::doubleClickSpeed();
    Window::setDoubleClickSpeed(300);
    REQUIRE(Window::doubleClickSpeed() == 300);
    Window::setDoubleClickSpeed(original);
  }
}

TEST_CASE("Default DPI scale is positive", "[windowing]") {
  float scale = defaultDpiScale();
  REQUIRE(scale > 0.0f);
}

TEST_CASE("isMobileDevice platform detection", "[windowing]") {
#if VISAGE_IOS
  REQUIRE(isMobileDevice() == true);
#elif VISAGE_MAC || VISAGE_WINDOWS || VISAGE_LINUX
  REQUIRE(isMobileDevice() == false);
#endif
}

TEST_CASE("computeWindowBounds returns valid dimensions", "[windowing]") {
  using namespace visage::dimension;
  IBounds bounds = computeWindowBounds(100_px, 200_px);
  REQUIRE(bounds.width() > 0);
  REQUIRE(bounds.height() > 0);
}

TEST_CASE("createWindow returns valid window", "[windowing]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);
}

TEST_CASE("Window DPI scale can be set", "[windowing]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  window->setDpiScale(2.0f);
  REQUIRE(window->dpiScale() == 2.0f);
}

TEST_CASE("Window coordinate conversion", "[windowing]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  window->setDpiScale(2.0f);

  IPoint native = window->convertToNative({ 50.0f, 75.0f });
  REQUIRE(native.x == 100);
  REQUIRE(native.y == 150);

  Point logical = window->convertToLogical({ 100, 150 });
  REQUIRE(logical.x == Catch::Approx(50.0f));
  REQUIRE(logical.y == Catch::Approx(75.0f));
}

TEST_CASE("Clipboard round-trip", "[windowing]") {
  std::string test_text = "visage clipboard test";
  setClipboardText(test_text);
  std::string result = readClipboardText();
  REQUIRE(result == test_text);
}

TEST_CASE("Window handleMouseDown accepts pointer_id parameter", "[windowing]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  SECTION("Default pointer_id 0 does not crash without event handler") {
    window->handleMouseDown(kMouseButtonLeft, 10, 10, kMouseButtonLeft, 0);
    window->handleMouseUp(kMouseButtonLeft, 10, 10, 0, 0);
  }

  SECTION("Non-zero pointer_id does not crash without event handler") {
    window->handleMouseDown(kMouseButtonLeft, 10, 10, kMouseButtonLeft, 0, 1);
    window->handleMouseMove(15, 15, kMouseButtonLeft, 0, 1);
    window->handleMouseUp(kMouseButtonLeft, 15, 15, 0, 0, 1);
  }
}

#if VISAGE_IOS
TEST_CASE("iOS window max dimensions are screen-sized", "[windowing][ios]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  IPoint max_dims = window->maxWindowDimensions();
  REQUIRE(max_dims.x > 0);
  REQUIRE(max_dims.y > 0);
}

TEST_CASE("createPluginWindow returns valid window on iOS", "[windowing][ios]") {
  using namespace visage::dimension;
  auto window = createPluginWindow(200_px, 300_px, nullptr);
  REQUIRE(window != nullptr);
}

TEST_CASE("iOS window show/hide cycle", "[windowing][ios]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  window->show();
  REQUIRE(window->isShowing() == true);

  window->hide();
  REQUIRE(window->isShowing() == false);
}

TEST_CASE("iOS window close stops showing", "[windowing][ios]") {
  using namespace visage::dimension;
  auto window = createWindow(100_px, 100_px);
  REQUIRE(window != nullptr);

  window->show();
  REQUIRE(window->isShowing() == true);

  window->close();
  REQUIRE(window->isShowing() == false);
}

TEST_CASE("iOS window DPI scale from constructor", "[windowing][ios]") {
  float scale = defaultDpiScale();
  using namespace visage::dimension;
  auto window = createWindow(200_px, 300_px);
  REQUIRE(window != nullptr);

  // Default scale should match device scale
  REQUIRE(window->dpiScale() == Catch::Approx(scale));
}
#endif
