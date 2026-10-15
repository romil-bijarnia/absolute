// SPDX-License-Identifier: MIT
#include "dock.h"

#include <LayerShellQt/Shell>

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

int main(int argc, char **argv)
{
    LayerShellQt::Shell::useLayerShell();
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("absolute-dock"));
    app.setDesktopFileName(QStringLiteral("org.absolute.Dock"));
    app.setQuitOnLastWindowClosed(false);
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    Dock dock;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("dockHost"), &dock);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        return 1;
    }
    dock.attach(window);
    window->show();
    return app.exec();
}
