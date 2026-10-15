// SPDX-License-Identifier: MIT
#include "spotlight.h"

#include <LayerShellQt/Shell>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

// One instance owns org.absolute.Spotlight; later invocations ask it to toggle.
int main(int argc, char **argv)
{
    LayerShellQt::Shell::useLayerShell();
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("absolute-spotlight"));
    app.setDesktopFileName(QStringLiteral("org.absolute.Spotlight"));
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    const QStringList arguments = app.arguments();
    const bool toggleOnly = arguments.contains(QStringLiteral("--toggle"));
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.interface()->isServiceRegistered(QStringLiteral("org.absolute.Spotlight"))) {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.absolute.Spotlight"), QStringLiteral("/App"),
                                                           QStringLiteral("org.absolute.Spotlight"), toggleOnly ? QStringLiteral("toggle") : QStringLiteral("show"));
        bus.call(call);
        return 0;
    }

    Spotlight spotlight;
    bus.registerObject(QStringLiteral("/App"), &spotlight, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties);
    bus.registerService(QStringLiteral("org.absolute.Spotlight"));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("spotlight"), &spotlight);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        return 1;
    }
    spotlight.attach(window);
    // Started by the shortcut: show at once. Started as a service: stay hidden.
    if (toggleOnly || arguments.contains(QStringLiteral("--show"))) {
        spotlight.show();
    }
    return app.exec();
}
