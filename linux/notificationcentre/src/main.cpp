// SPDX-License-Identifier: MIT
#include "centre.h"

#include <LayerShellQt/Shell>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

// One instance owns org.absolute.NotificationCentre; later invocations ask it to toggle.
int main(int argc, char **argv)
{
    LayerShellQt::Shell::useLayerShell();
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("absolute-notificationcentre"));
    app.setApplicationDisplayName(QStringLiteral("Notification Centre"));
    app.setDesktopFileName(QStringLiteral("org.absolute.NotificationCentre"));
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    // This process is the notification service: libnotificationmanager registers
    // org.freedesktop.Notifications for the "DBus master", replacing any other owner.
    app.setProperty("_plasma_dbus_master", true);

    const QStringList arguments = app.arguments();
    const bool toggleOnly = arguments.contains(QStringLiteral("--toggle"));
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.interface()->isServiceRegistered(QStringLiteral("org.absolute.NotificationCentre"))) {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.absolute.NotificationCentre"), QStringLiteral("/App"),
                                                           QStringLiteral("org.absolute.NotificationCentre"), toggleOnly ? QStringLiteral("toggle") : QStringLiteral("show"));
        bus.call(call);
        return 0;
    }

    Centre centre;
    bus.registerObject(QStringLiteral("/App"), &centre, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties);
    bus.registerService(QStringLiteral("org.absolute.NotificationCentre"));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("centre"), &centre);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        return 1;
    }
    centre.attach(window);
    if (toggleOnly || arguments.contains(QStringLiteral("--show"))) {
        centre.show();
    }
    return app.exec();
}
