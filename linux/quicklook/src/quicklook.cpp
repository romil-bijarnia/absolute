// SPDX-License-Identifier: MIT
#include "quicklook.h"

#include <KApplicationTrader>
#include <KFormat>
#include <KIO/OpenUrlJob>
#include <KService>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QQuickWindow>
#include <QRegion>
#include <QTextStream>

QuickLook::QuickLook(QObject *parent)
    : QObject(parent)
{
}

void QuickLook::attach(QQuickWindow *window)
{
    m_window = window;
    // A layer surface floats above the windows, is centred by the compositor and
    // never appears as a task in the Dock, as the Mac's Quick Look panel behaves.
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setScope(QStringLiteral("absolute-quicklook"));
    layer->setAnchors(LayerShellQt::Window::Anchors());
    layer->setExclusiveZone(0);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    connect(window, &QWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible) {
            KWindowEffects::enableBlurBehind(window, true, QRegion(QRect(0, 0, window->width(), window->height())));
        }
    });
}

void QuickLook::show(const QStringList &files)
{
    QStringList kept;
    for (const QString &file : files) {
        const QUrl url = QUrl::fromUserInput(file, QDir::currentPath(), QUrl::AssumeLocalFile);
        if (url.isLocalFile() && QFileInfo::exists(url.toLocalFile())) {
            kept << url.toLocalFile();
        }
    }
    if (kept.isEmpty()) {
        return;
    }
    m_files = kept;
    m_index = 0;
    Q_EMIT filesChanged();
    inspect();
    if (m_window) {
        m_window->show();
        m_window->requestActivate();
    }
}

void QuickLook::setIndex(int index)
{
    if (m_files.isEmpty()) {
        return;
    }
    const int bounded = ((index % m_files.size()) + m_files.size()) % m_files.size();
    if (bounded == m_index) {
        return;
    }
    m_index = bounded;
    inspect();
}

QUrl QuickLook::url() const
{
    return m_files.isEmpty() ? QUrl() : QUrl::fromLocalFile(m_files.at(m_index));
}

QString QuickLook::fileName() const
{
    return m_files.isEmpty() ? QString() : QFileInfo(m_files.at(m_index)).fileName();
}

void QuickLook::next()
{
    setIndex(m_index + 1);
}

void QuickLook::previous()
{
    setIndex(m_index - 1);
}

void QuickLook::open()
{
    if (m_files.isEmpty()) {
        return;
    }
    auto *job = new KIO::OpenUrlJob(url());
    job->setRunExecutables(false);
    job->start();
    close();
}

void QuickLook::close()
{
    if (m_window) {
        m_window->hide();
    }
}

// Reads the current file's type, size, dates, icon and (for text) its content.
void QuickLook::inspect()
{
    m_text.clear();
    m_kind = QStringLiteral("other");
    if (m_files.isEmpty()) {
        Q_EMIT indexChanged();
        return;
    }
    const QString path = m_files.at(m_index);
    const QFileInfo info(path);
    QMimeDatabase db;
    const QMimeType mime = db.mimeTypeForFile(info);
    m_mimeName = mime.comment();
    m_iconName = mime.iconName();
    const QString name = mime.name();
    if (info.isDir()) {
        m_kind = QStringLiteral("folder");
    } else if (name.startsWith(QLatin1String("image/")) && !name.contains(QLatin1String("svg"))) {
        m_kind = QStringLiteral("image");
    } else if (name == QLatin1String("application/pdf")) {
        m_kind = QStringLiteral("pdf");
    } else if (name.startsWith(QLatin1String("video/"))) {
        m_kind = QStringLiteral("video");
    } else if (name.startsWith(QLatin1String("audio/"))) {
        m_kind = QStringLiteral("audio");
    } else if (name.startsWith(QLatin1String("text/")) || mime.inherits(QStringLiteral("text/plain")) || name.contains(QLatin1String("json")) || name.contains(QLatin1String("xml"))) {
        m_kind = QStringLiteral("text");
        QFile file(path);
        if (file.open(QIODevice::ReadOnly)) {
            m_text = QString::fromUtf8(file.read(2 * 1024 * 1024));
            if (file.size() > 2 * 1024 * 1024) {
                m_text += QStringLiteral("\n…");
            }
        }
    }
    KFormat format;
    const QString size = info.isDir() ? QString() : format.formatByteSize(info.size());
    const QString modified = QLocale().toString(info.lastModified(), QLocale::ShortFormat);
    m_details = size.isEmpty() ? QStringLiteral("%1 · %2").arg(m_mimeName, modified) : QStringLiteral("%1 · %2 · %3").arg(m_mimeName, size, modified);
    const KService::Ptr service = KApplicationTrader::preferredService(name);
    m_openWith = service ? service->name() : QString();
    Q_EMIT indexChanged();
}
