# Absolute Spotlight

The centred search panel: a glass field a fifth of the way down the screen,
results growing below it, arrow keys to choose, Enter to run, Escape to
dismiss. Results come from Plasma's search backend (milou over KRunner), so
applications, files, calculations and settings all appear.

`absolute-spotlight` runs as a hidden service started with the session and
owns `org.absolute.Spotlight` on the session bus; `absolute-spotlight --toggle`
(or the `toggle`/`show`/`hide` methods on `/App`) shows and hides it. The
installer binds Meta+Space to the launcher entry and moves KRunner to
Alt+Space. Built and installed by `bash script/absolute_surface.sh --dock`.
