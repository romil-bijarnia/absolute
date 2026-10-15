// SPDX-License-Identifier: MIT
#include "spotlight.h"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QGuiApplication>
#include <QPainterPath>
#include <QQuickWindow>
#include <QScreen>

Spotlight::Spotlight(QObject *parent)
    : QObject(parent)
{
}

void Spotlight::attach(QQuickWindow *window)
{
    m_window = window;
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setScope(QStringLiteral("absolute-spotlight"));
    layer->setExclusiveZone(-1);
    // Centred horizontally by the compositor (no side anchors); a fifth of the way down.
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop));
    const int top = QGuiApplication::primaryScreen() ? int(QGuiApplication::primaryScreen()->geometry().height() * 0.2) : 200;
    layer->setMargins(QMargins(0, top, 0, 0));
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    connect(window, &QWindow::visibleChanged, this, [this](bool visible) {
        if (visible) {
            applyGlass();
            Q_EMIT requestFocus();
        }
        Q_EMIT shownChanged();
    });
}

bool Spotlight::shown() const
{
    return m_window && m_window->isVisible();
}

void Spotlight::toggle()
{
    if (shown()) {
        hide();
    } else {
        show();
    }
}

void Spotlight::show()
{
    if (!m_window) {
        return;
    }
    m_window->show();
    m_window->requestActivate();
    Q_EMIT requestFocus();
}

void Spotlight::hide()
{
    if (m_window) {
        m_window->hide();
    }
}

void Spotlight::setGlass(qreal x, qreal y, qreal width, qreal height, qreal radius)
{
    m_glass = QRectF(x, y, width, height);
    m_radius = radius;
    applyGlass();
}

void Spotlight::applyGlass()
{
    if (!m_window || !m_window->isVisible() || m_glass.isEmpty()) {
        return;
    }
    QPainterPath path;
    path.addRoundedRect(m_glass, m_radius, m_radius);
    const QRegion region(path.toFillPolygon().toPolygon());
    KWindowEffects::enableBlurBehind(m_window, true, region);
    KWindowEffects::enableBackgroundContrast(m_window, true, 0.55, 1.0, 0.9, region);
}
