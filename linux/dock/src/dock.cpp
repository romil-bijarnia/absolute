// SPDX-License-Identifier: MIT
#include "dock.h"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDebug>
#include <QDBusPendingCall>
#include <QDesktopServices>
#include <QDir>
#include <QPainterPath>
#include <QProcess>
#include <QQuickWindow>
#include <QRegion>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

Dock::Dock(QObject *parent)
    : QObject(parent)
{
    loadConfig();
    const QString trash = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash/files");
    QDir().mkpath(trash);
    m_trashWatcher.addPath(trash);
    connect(&m_trashWatcher, &QFileSystemWatcher::directoryChanged, this, &Dock::trashChanged);
}

void Dock::loadConfig()
{
    // ~/.config/absolute/dockrc, INI. Defaults follow the Mac's own Dock defaults.
    QSettings settings(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/absolute/dockrc"), QSettings::IniFormat);
    m_tileSize = settings.value(QStringLiteral("tileSize"), 64).toInt();
    m_largeSize = settings.value(QStringLiteral("largeSize"), 128).toInt();
    m_magnification = settings.value(QStringLiteral("magnification"), true).toBool();
    m_autohide = settings.value(QStringLiteral("autohide"), false).toBool();
    m_launchpadCommand = settings.value(QStringLiteral("launchpadCommand"), QStringLiteral("absolute-launchpad")).toString();
    m_launchers = settings.value(QStringLiteral("launchers")).toStringList();
    if (m_launchers.isEmpty()) {
        m_launchers = {
            QStringLiteral("applications:org.kde.dolphin.desktop"),
            QStringLiteral("applications:org.mozilla.firefox.desktop"),
            QStringLiteral("applications:org.kde.gwenview.desktop"),
            QStringLiteral("applications:org.kde.elisa.desktop"),
            QStringLiteral("applications:org.kde.kate.desktop"),
            QStringLiteral("applications:org.keepassxc.KeePassXC.desktop"),
            QStringLiteral("applications:org.kde.konsole.desktop"),
            QStringLiteral("applications:org.kde.discover.desktop"),
            QStringLiteral("applications:systemsettings.desktop"),
        };
    }
}

void Dock::attach(QQuickWindow *window)
{
    m_window = window;
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    layer->setScope(QStringLiteral("dock"));
    layer->setExclusiveZone(m_exclusiveZone);
    // Blur regions need the native surface, which exists once the window is visible.
    connect(window, &QWindow::visibleChanged, this, [this](bool visible) {
        if (visible) {
            applyGlass();
        }
    });
}

bool Dock::trashEmpty() const
{
    const QString trash = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash/files");
    return QDir(trash).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden).isEmpty();
}

QString Dock::homePath() const
{
    return QDir::homePath();
}

void Dock::setGlass(qreal x, qreal y, qreal width, qreal height, qreal radius)
{
    m_glass = QRectF(x, y, width, height);
    m_glassRadius = radius;
    applyGlass();
}

void Dock::applyGlass()
{
    if (!m_window || !m_window->isVisible() || m_glass.isEmpty()) {
        return;
    }
    const qreal x = m_glass.x(), y = m_glass.y(), width = m_glass.width(), height = m_glass.height(), radius = m_glassRadius;
    QPainterPath path;
    path.addRoundedRect(QRectF(x, y, width, height), radius, radius);
    const QRegion glass(path.toFillPolygon().toPolygon());
    KWindowEffects::enableBlurBehind(m_window, true, glass);
    KWindowEffects::enableBackgroundContrast(m_window, true, 0.6, 1.0, 0.9, glass);
    // Everything above the glass, between its edges, must take clicks: magnified tiles
    // rise well above it. The rest of the strip stays transparent to input.
    m_window->setMask(QRegion(QRect(int(x), 0, int(width), int(y + height + 1))));
}

void Dock::setExclusiveZone(int pixels)
{
    m_exclusiveZone = pixels;
    if (m_window) {
        LayerShellQt::Window::get(m_window)->setExclusiveZone(pixels);
    }
}

void Dock::openPath(const QString &path)
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void Dock::openTrash()
{
    QProcess::startDetached(QStringLiteral("dolphin"), {QStringLiteral("trash:/")});
}

void Dock::runCommand(const QString &command)
{
    QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command});
}

void Dock::openLaunchpad()
{
    if (!QStandardPaths::findExecutable(m_launchpadCommand).isEmpty()) {
        runCommand(m_launchpadCommand);
        return;
    }
    // Until Absolute's Launchpad exists, the search panel is the nearest thing.
    if (!QStandardPaths::findExecutable(QStringLiteral("absolute-spotlight"), {QDir::homePath() + QStringLiteral("/.local/bin")}).isEmpty()) {
        QProcess::startDetached(QDir::homePath() + QStringLiteral("/.local/bin/absolute-spotlight"), {QStringLiteral("--toggle")});
        return;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.krunner"), QStringLiteral("/App"),
                                                       QStringLiteral("org.kde.krunner.App"), QStringLiteral("display"));
    QDBusConnection::sessionBus().asyncCall(call);
}

void Dock::trace(const QString &message)
{
    qWarning().noquote() << "Dock:" << message;
}

void Dock::showAllWindows()
{
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"),
                                                       QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
    call << QStringLiteral("ExposeClass");
    QDBusConnection::sessionBus().asyncCall(call);
}
