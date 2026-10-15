// SPDX-License-Identifier: MIT
#pragma once

#include <KService>

#include <QAbstractListModel>
#include <QObject>
#include <QSortFilterProxyModel>

class QQuickWindow;

// Every application with a menu entry, sorted by name, with its icon.
class AppsModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        IconRole,
        DesktopIdRole,
        CommentRole,
    };
    explicit AppsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reload();
    KService::Ptr service(int row) const;

private:
    KService::List m_services;
};

// Shows and hides the grid; reachable over DBus as org.absolute.Launchpad /App.
class Launchpad : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.absolute.Launchpad")
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)
    Q_PROPERTY(QObject *apps READ apps CONSTANT)

public:
    explicit Launchpad(QObject *parent = nullptr);

    void attach(QQuickWindow *window);
    bool shown() const;
    QObject *apps() { return &m_filtered; }

    Q_INVOKABLE void setFilter(const QString &text);
    Q_INVOKABLE void launch(int filteredRow);

public Q_SLOTS:
    void toggle();
    void show();
    void hide();

Q_SIGNALS:
    void shownChanged();
    void requestFocus();

private:
    QQuickWindow *m_window = nullptr;
    AppsModel m_apps;
    QSortFilterProxyModel m_filtered;
};
