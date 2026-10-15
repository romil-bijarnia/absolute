// SPDX-License-Identifier: MIT
#include "centre.h"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QQuickWindow>
#include <QRegion>

Centre::Centre(QObject *parent)
    : QObject(parent)
{
}

void Centre::attach(QQuickWindow *window)
{
    m_window = window;
    // A top-layer surface along the right edge, below the menu bar's exclusive zone.
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setScope(QStringLiteral("absolute-notificationcentre"));
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorRight));
    layer->setExclusiveZone(0);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    connect(window, &QWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible) {
            KWindowEffects::enableBlurBehind(window, true, QRegion(QRect(0, 0, window->width(), window->height())));
        }
        Q_EMIT shownChanged();
    });
}

bool Centre::shown() const
{
    return m_window && m_window->isVisible();
}

void Centre::toggle()
{
    if (shown()) {
        hide();
    } else {
        show();
    }
}

void Centre::show()
{
    if (m_window) {
        m_window->show();
        m_window->requestActivate();
    }
}

void Centre::hide()
{
    if (m_window) {
        m_window->hide();
    }
}
