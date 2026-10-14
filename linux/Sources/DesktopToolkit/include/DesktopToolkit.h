#ifndef ABSOLUTE_DESKTOP_TOOLKIT_H
#define ABSOLUTE_DESKTOP_TOOLKIT_H

typedef struct ALHost ALHost;
typedef struct ALFilesView ALFilesView;
typedef struct { double x, y, width, height; int valid; } ALRect;
typedef void (*ALActionCallback)(void *context, int action, const char *window_id,
                                const char *value, double a, double b);
typedef void (*ALApplicationCallback)(void *context, const char *name,
                                     const char *path, const char *identifier);

enum {
    AL_TICK = 0, AL_NEW_FILES, AL_SHOW_FILES, AL_SHOW_DESKTOP, AL_FOCUS,
    AL_CLOSE, AL_MINIMIZE, AL_MAXIMIZE, AL_MOVE, AL_RESIZE,
    AL_NAVIGATE, AL_BACK, AL_FORWARD, AL_UP, AL_FILTER, AL_HIDDEN,
    AL_SORT, AL_VIEW, AL_SELECT, AL_OPEN, AL_INFO, AL_REVEAL, AL_PREVIEW,
    AL_LAUNCHER, AL_LAUNCHER_FILTER, AL_LAUNCHER_SELECT, AL_LAUNCHER_ACCEPT,
    AL_LAUNCHER_MOVE, AL_DISMISS, AL_WALLPAPER, AL_TERMINAL, AL_QUIT
};

ALHost *al_host_new(ALActionCallback callback, void *context);
void al_host_run(ALHost *host);
void al_host_free(ALHost *host);
void al_host_quit(ALHost *host);
void al_host_set_wallpaper(ALHost *host, const char *wallpaper);
void al_host_set_notice(ALHost *host, const char *message);
ALRect al_host_rect(ALHost *host, const char *role);

ALFilesView *al_files_new(ALHost *host, const char *identifier);
void al_files_destroy(ALFilesView *view);
void al_files_frame(ALFilesView *view, double x, double y, double width, double height, int visible);
void al_files_raise(ALFilesView *view);
void al_files_location(ALFilesView *view, const char *title, const char *path,
                       const char *filter, int back, int forward, int hidden, int sort, int grid);
void al_files_favorite(ALFilesView *view, const char *label, const char *path, const char *icon);
void al_files_clear(ALFilesView *view);
void al_files_entry(ALFilesView *view, const char *path, const char *name,
                    const char *kind, const char *modified, const char *size, int folder);
void al_files_selected(ALFilesView *view, const char *path);
void al_files_status(ALFilesView *view, const char *message);
ALRect al_files_rect(ALFilesView *view, const char *role);

void al_host_dialog(ALHost *host, const char *title, const char *text, int can_reveal);
void al_host_dismiss(ALHost *host);
void al_launcher_show(ALHost *host);
void al_launcher_clear(ALHost *host);
void al_launcher_entry(ALHost *host, const char *name, const char *path);
void al_launcher_selected(ALHost *host, int index);
void al_applications(ALApplicationCallback callback, void *context);
int al_launch_application(const char *path);
int al_open_file(const char *path);
void al_copy_text(ALHost *host, const char *text);

#endif
