// SPDX-License-Identifier: MIT
#include "quicklook.h"

#include <LayerShellQt/Shell>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

// absolute-quicklook FILE...: previews the files. A running instance takes over.
int main(int argc, char **argv)
{
    LayerShellQt::Shell::useLayerShell();
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("absolute-quicklook"));
    app.setApplicationDisplayName(QStringLiteral("Quick Look"));
    app.setDesktopFileName(QStringLiteral("org.absolute.QuickLook"));
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    QStringList files = app.arguments().mid(1);
    files.removeAll(QStringLiteral("--"));
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.interface()->isServiceRegistered(QStringLiteral("org.absolute.QuickLook"))) {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.absolute.QuickLook"), QStringLiteral("/App"),
                                                           QStringLiteral("org.absolute.QuickLook"), QStringLiteral("show"));
        call << files;
        bus.call(call);
        return 0;
    }

    QuickLook quicklook;
    bus.registerObject(QStringLiteral("/App"), &quicklook, QDBusConnection::ExportAllSlots);
    bus.registerService(QStringLiteral("org.absolute.QuickLook"));

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("quicklook"), &quicklook);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        return 1;
    }
    quicklook.attach(window);
    // Without files the process stays as the hidden service; the window closes the
    // process when it was started for a set of files and the user dismisses it.
    QObject::connect(window, &QWindow::visibleChanged, &app, [&app, &files](bool visible) {
        if (!visible && !files.isEmpty()) {
            app.quit();
        }
    });
    if (!files.isEmpty()) {
        quicklook.show(files);
    }
    return app.exec();
}
