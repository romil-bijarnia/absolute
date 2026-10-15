// SPDX-License-Identifier: MIT
#include "launchpad.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QCollator>
#include <QIcon>
#include <QQuickWindow>
#include <QRegion>

AppsModel::AppsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    reload();
}

void AppsModel::reload()
{
    beginResetModel();
    m_services = KApplicationTrader::query([](const KService::Ptr &service) {
        return service->isApplication() && !service->noDisplay() && !service->exec().isEmpty();
    });
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(m_services.begin(), m_services.end(), [&collator](const KService::Ptr &a, const KService::Ptr &b) {
        return collator.compare(a->name(), b->name()) < 0;
    });
    endResetModel();
}

int AppsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_services.size();
}

QVariant AppsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_services.size()) {
        return {};
    }
    const KService::Ptr &service = m_services.at(index.row());
    switch (role) {
    case NameRole:
    case Qt::DisplayRole:
        return service->name();
    case IconRole:
        return QIcon::fromTheme(service->icon(), QIcon::fromTheme(QStringLiteral("application-x-executable")));
    case DesktopIdRole:
        return service->storageId();
    case CommentRole:
        return service->comment();
    }
    return {};
}

QHash<int, QByteArray> AppsModel::roleNames() const
{
    return {{NameRole, "name"}, {IconRole, "icon"}, {DesktopIdRole, "desktopId"}, {CommentRole, "comment"}};
}

KService::Ptr AppsModel::service(int row) const
{
    return row >= 0 && row < m_services.size() ? m_services.at(row) : KService::Ptr();
}

Launchpad::Launchpad(QObject *parent)
    : QObject(parent)
{
    m_filtered.setSourceModel(&m_apps);
    m_filtered.setFilterRole(AppsModel::NameRole);
    m_filtered.setFilterCaseSensitivity(Qt::CaseInsensitive);
}

void Launchpad::attach(QQuickWindow *window)
{
    m_window = window;
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setScope(QStringLiteral("absolute-launchpad"));
    layer->setExclusiveZone(-1);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    connect(window, &QWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible) {
            KWindowEffects::enableBlurBehind(window, true, QRegion(QRect(0, 0, window->width(), window->height())));
            Q_EMIT requestFocus();
        }
        Q_EMIT shownChanged();
    });
    connect(window, &QWindow::widthChanged, this, [this, window]() {
        if (window->isVisible()) {
            KWindowEffects::enableBlurBehind(window, true, QRegion(QRect(0, 0, window->width(), window->height())));
        }
    });
}

bool Launchpad::shown() const
{
    return m_window && m_window->isVisible();
}

void Launchpad::setFilter(const QString &text)
{
    m_filtered.setFilterFixedString(text);
}

void Launchpad::launch(int filteredRow)
{
    const QModelIndex source = m_filtered.mapToSource(m_filtered.index(filteredRow, 0));
    const KService::Ptr service = m_apps.service(source.row());
    if (!service) {
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(service);
    job->start();
    hide();
}

void Launchpad::toggle()
{
    if (shown()) {
        hide();
    } else {
        show();
    }
}

void Launchpad::show()
{
    if (!m_window) {
        return;
    }
    m_apps.reload();
    m_window->show();
    m_window->requestActivate();
    Q_EMIT requestFocus();
}

void Launchpad::hide()
{
    if (m_window) {
        m_window->hide();
    }
}
