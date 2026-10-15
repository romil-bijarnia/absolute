# Absolute Notification Centre

Absolute's own notification service, popups and history. The process registers
`org.freedesktop.Notifications` as the session's notification server (through
KDE's libnotificationmanager, the same library behind Plasma's applet), so Plasma's
notifications applet stays out of the tray. New notifications appear as cards at
the top right under the menu bar with the application name, title, body and action
buttons, and expire after their timeout unless hovered. The history slides in at the
right edge when the menu bar clock (`org.absolute.clock`) is clicked, grouped by
application with a clear button per group and "Clear All"; Escape hides it.

Do Not Disturb from Control Centre applies here as well: the library reads the
same notification settings, so inhibited notifications are held back.

## Reaching it

- `absolute-notificationcentre --toggle`, or DBus `org.absolute.NotificationCentre
  /App toggle|show|hide`.
- The hidden service copy starts with the session (`~/.config/autostart`), installed
  by `script/absolute_surface.sh --dock` together with the clock applet.

## Not yet

Widgets in the centre (calendar, weather), a swipe from the right edge, the
notification grouping count badge, reply fields, and job progress beyond a
percentage line.
