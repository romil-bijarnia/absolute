// SPDX-License-Identifier: MIT
#include "launchpad.h"

#include <LayerShellQt/Shell>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

// One instance owns org.absolute.Launchpad; later invocations ask it to toggle.
int main(int argc, char **argv)
{
    LayerShellQt::Shell::useLayerShell();
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("absolute-launchpad"));
    app.setDesktopFileName(QStringLiteral("org.absolute.Launchpad"));
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    const QStringList arguments = app.arguments();
    const bool toggleOnly = arguments.contains(QStringLiteral("--toggle"));
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.interface()->isServiceRegistered(QStringLiteral("org.absolute.Launchpad"))) {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.absolute.Launchpad"), QStringLiteral("/App"),
                                                           QStringLiteral("org.absolute.Launchpad"), toggleOnly ? QStringLiteral("toggle") : QStringLiteral("show"));
        bus.call(call);
        return 0;
    }

    Launchpad launchpad;
    bus.registerObject(QStringLiteral("/App"), &launchpad, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllProperties);
    bus.registerService(QStringLiteral("org.absolute.Launchpad"));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("launchpad"), &launchpad);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        return 1;
    }
    launchpad.attach(window);
    if (toggleOnly || arguments.contains(QStringLiteral("--show"))) {
        launchpad.show();
    }
    return app.exec();
}
