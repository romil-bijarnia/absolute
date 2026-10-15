// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>

class QQuickWindow;

// Shows and hides the panel; reachable over DBus as org.absolute.NotificationCentre /App.
class Centre : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.absolute.NotificationCentre")
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)

public:
    explicit Centre(QObject *parent = nullptr);

    void attach(QQuickWindow *window);
    bool shown() const;

public Q_SLOTS:
    void toggle();
    void show();
    void hide();

Q_SIGNALS:
    void shownChanged();

private:
    QQuickWindow *m_window = nullptr;
};
