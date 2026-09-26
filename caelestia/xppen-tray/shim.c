// Keep XP-Pen's PenTablet alive when its window is closed, so the tray icon
// stays and clicking it brings the window back (Discord-style).
#define _GNU_SOURCE
#include <dlfcn.h>
extern void _ZN15QGuiApplication25setQuitOnLastWindowClosedEb(int);
int _ZN12QApplication4execEv(void) {
    static int (*real)(void);
    if (!real) real = dlsym(RTLD_NEXT, "_ZN12QApplication4execEv");
    _ZN15QGuiApplication25setQuitOnLastWindowClosedEb(0);
    return real();
}
