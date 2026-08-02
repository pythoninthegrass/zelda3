// SDL_GetKeyFromName table for the Zig-port test harnesses. The real
// function stays in SDL (config.c/config.zig call it to resolve [KeyMap]
// value names); linking SDL into the unit/difftest binaries just for key
// name lookups is overkill, so this covers the names those fixtures use.
#include <SDL_keycode.h>
#include <string.h>

typedef struct KeyName { const char *name; SDL_Keycode code; } KeyName;
static const KeyName kKeyNames[] = {
  {"Backspace", SDLK_BACKSPACE}, {"Tab", SDLK_TAB}, {"Return", SDLK_RETURN},
  {"Escape", SDLK_ESCAPE}, {"Space", SDLK_SPACE},
  {"F1", SDLK_F1}, {"F2", SDLK_F2}, {"F3", SDLK_F3}, {"F4", SDLK_F4},
  {"F5", SDLK_F5}, {"F6", SDLK_F6}, {"F7", SDLK_F7}, {"F8", SDLK_F8},
  {"F9", SDLK_F9}, {"F10", SDLK_F10}, {"F11", SDLK_F11}, {"F12", SDLK_F12},
  {"Left", SDLK_LEFT}, {"Right", SDLK_RIGHT}, {"Up", SDLK_UP}, {"Down", SDLK_DOWN},
  {"LCtrl", SDLK_LCTRL}, {"LShift", SDLK_LSHIFT}, {"LAlt", SDLK_LALT},
  {"RCtrl", SDLK_RCTRL}, {"RShift", SDLK_RSHIFT}, {"RAlt", SDLK_RALT},
};

SDL_Keycode SDL_GetKeyFromName(const char *name) {
  if (name[0] && !name[1]) {
    char c = name[0];
    if (c >= 'A' && c <= 'Z') c += 32; // SDL keycodes are lowercase
    return (SDL_Keycode)c;
  }
  for (unsigned i = 0; i < sizeof(kKeyNames) / sizeof(kKeyNames[0]); i++)
    if (strcmp(name, kKeyNames[i].name) == 0)
      return kKeyNames[i].code;
  return SDLK_UNKNOWN;
}
