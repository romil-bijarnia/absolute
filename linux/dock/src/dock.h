// SPDX-License-Identifier: MIT
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QRect>
#include <QStringList>

class QQuickWindow;

// The native side of the Dock: layer-shell placement, blur and input regions,
// configuration, and the few desktop actions QML cannot do itself.
class Dock : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int tileSize READ tileSize CONSTANT)
    Q_PROPERTY(int largeSize READ largeSize CONSTANT)
    Q_PROPERTY(bool magnification READ magnification CONSTANT)
    Q_PROPERTY(bool autohide READ autohide CONSTANT)
    Q_PROPERTY(QStringList launchers READ launchers CONSTANT)
    Q_PROPERTY(bool trashEmpty READ trashEmpty NOTIFY trashChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)

public:
    explicit Dock(QObject *parent = nullptr);

    void attach(QQuickWindow *window);

    int tileSize() const { return m_tileSize; }
    int largeSize() const { return m_largeSize; }
    bool magnification() const { return m_magnification; }
    bool autohide() const { return m_autohide; }
    QStringList launchers() const { return m_launchers; }
    bool trashEmpty() const;
    QString homePath() const;

    // The glass rectangle in window coordinates: blur and contrast behind it, and the
    // input region is the column above it so magnified tiles stay clickable.
    Q_INVOKABLE void setGlass(qreal x, qreal y, qreal width, qreal height, qreal radius);
    Q_INVOKABLE void setExclusiveZone(int pixels);
    // Autohide: while hidden only a 2 px strip along the screen edge takes the pointer;
    // while shown, the band from 10 px beyond the glass to the edge (the Mac's shape).
    Q_INVOKABLE void setHiddenStrip(bool hidden);
    Q_INVOKABLE void openPath(const QString &path);
    Q_INVOKABLE void openTrash();
    Q_INVOKABLE void runCommand(const QString &command);
    Q_INVOKABLE void openLaunchpad();
    Q_INVOKABLE void showAllWindows();
    Q_INVOKABLE void trace(const QString &message);

Q_SIGNALS:
    void trashChanged();

private:
    void loadConfig();

    void applyGlass();

    QQuickWindow *m_window = nullptr;
    QRectF m_glass;
    qreal m_glassRadius = 0;
    int m_exclusiveZone = 0;
    QFileSystemWatcher m_trashWatcher;
    int m_tileSize = 64;
    int m_largeSize = 128;
    bool m_magnification = true;
    bool m_autohide = false;
    bool m_hiddenStrip = false;
    QStringList m_launchers;
    QString m_launchpadCommand;
};
