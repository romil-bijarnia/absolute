// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>
#include <QRectF>

class QQuickWindow;

// Shows and hides the panel; reachable over DBus as org.absolute.Spotlight /App.
class Spotlight : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.absolute.Spotlight")
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)

public:
    explicit Spotlight(QObject *parent = nullptr);

    void attach(QQuickWindow *window);
    bool shown() const;

public Q_SLOTS:
    void toggle();
    void show();
    void hide();
    // The panel's glass rectangle in window coordinates, for the blur behind it.
    void setGlass(qreal x, qreal y, qreal width, qreal height, qreal radius);

Q_SIGNALS:
    void shownChanged();
    void requestFocus();

private:
    void applyGlass();

    QQuickWindow *m_window = nullptr;
    QRectF m_glass;
    qreal m_radius = 0;
};
