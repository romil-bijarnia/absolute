// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>
#include <QStringList>
#include <QUrl>

class QQuickWindow;

// The files under preview and the one currently shown. Reachable over DBus as
// org.absolute.QuickLook /App so a second invocation replaces the current set.
class QuickLook : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.absolute.QuickLook")
    Q_PROPERTY(QStringList files READ files NOTIFY filesChanged)
    Q_PROPERTY(int index READ index WRITE setIndex NOTIFY indexChanged)
    Q_PROPERTY(QUrl url READ url NOTIFY indexChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY indexChanged)
    Q_PROPERTY(QString kind READ kind NOTIFY indexChanged)
    Q_PROPERTY(QString mimeName READ mimeName NOTIFY indexChanged)
    Q_PROPERTY(QString iconName READ iconName NOTIFY indexChanged)
    Q_PROPERTY(QString details READ details NOTIFY indexChanged)
    Q_PROPERTY(QString text READ text NOTIFY indexChanged)
    Q_PROPERTY(QString openWith READ openWith NOTIFY indexChanged)

public:
    explicit QuickLook(QObject *parent = nullptr);

    void attach(QQuickWindow *window);

    QStringList files() const { return m_files; }
    int index() const { return m_index; }
    void setIndex(int index);
    QUrl url() const;
    QString fileName() const;
    QString kind() const { return m_kind; }
    QString mimeName() const { return m_mimeName; }
    QString iconName() const { return m_iconName; }
    QString details() const { return m_details; }
    QString text() const { return m_text; }
    QString openWith() const { return m_openWith; }

    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void open();
    Q_INVOKABLE void close();

public Q_SLOTS:
    void show(const QStringList &files);

Q_SIGNALS:
    void filesChanged();
    void indexChanged();

private:
    void inspect();

    QQuickWindow *m_window = nullptr;
    QStringList m_files;
    int m_index = 0;
    QString m_kind, m_mimeName, m_iconName, m_details, m_text, m_openWith;
};
