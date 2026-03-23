/* GSDisplayServer+Eau.m - Fix popup menu window type
   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

/*
 * libs-back sets _NET_WM_WINDOW_TYPE_DIALOG instead of
 * _NET_WM_WINDOW_TYPE_POPUP_MENU for NSPopUpMenuWindowLevel windows
 * (XGServerWindow.m:3479). This causes the window manager to decorate
 * popup menus with frames/titlebars instead of mapping them undecorated.
 *
 * This category swizzles -setwindowlevel:: on XGServer to fix the
 * _NET_WM_WINDOW_TYPE property after the original method runs.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>

@implementation GSDisplayServer (EauPopupMenuFix)

+ (void) load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = NSClassFromString(@"XGServer");
    if (!cls)
      return;

    SEL origSel = @selector(setwindowlevel::);
    SEL swizSel = @selector(eau_setwindowlevel::);

    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizMethod = class_getInstanceMethod(self, swizSel);
    if (!origMethod || !swizMethod)
      return;

    /* Add our method to XGServer, then exchange implementations */
    class_addMethod(cls, swizSel,
                    method_getImplementation(swizMethod),
                    method_getTypeEncoding(swizMethod));
    Method addedMethod = class_getInstanceMethod(cls, swizSel);
    method_exchangeImplementations(origMethod, addedMethod);
  });
}

- (void) eau_setwindowlevel: (int)level : (int)win
{
  /* Call original (swizzled) */
  [self eau_setwindowlevel: level : win];

  /* Fix popup menu window type: libs-back sets DIALOG instead of POPUP_MENU */
  if (level == NSPopUpMenuWindowLevel)
    {
      /* Only fix actual menu panel windows. NSPopUpMenuWindowLevel is shared
         by tooltips, autocomplete, drag views, popovers, and other windows
         that must keep the default DIALOG type. */
      NSWindow *nswin = GSWindowWithNumber(win);
      if (!nswin)
        return;

      Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
      if (!menuPanelClass || ![nswin isKindOfClass: menuPanelClass])
        return;

      Display *dpy = (Display *)[self serverDevice];
      Window xwin = (Window)(uintptr_t)[self windowDevice: win];
      if (dpy && xwin)
        {
          Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
          Atom popupType = XInternAtom(dpy,
                                       "_NET_WM_WINDOW_TYPE_POPUP_MENU",
                                       False);
          XChangeProperty(dpy, xwin, wmType, XA_ATOM, 32, PropModeReplace,
                         (unsigned char *)&popupType, 1);
        }
    }
}

@end
