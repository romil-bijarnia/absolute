// SPDX-License-Identifier: MIT
#include "button.h"
#include "decoration.h"

#include <KDecoration3/DecoratedWindow>

#include <QPainter>
#include <QPainterPath>

namespace Absolute
{

Button::Button(KDecoration3::DecorationButtonType type, Decoration *decoration, QObject *parent)
    : KDecoration3::DecorationButton(type, decoration, parent)
{
    setGeometry(QRectF(0, 0, Metrics::LightDiameter, Metrics::LightDiameter));
    setVisible(isLight());
    // Any light hovered shows the glyphs on all three, as the Mac does.
    connect(this, &KDecoration3::DecorationButton::hoveredChanged, this, [this, decoration]() {
        bool any = false;
        const auto siblings = decoration->findChildren<Button *>();
        for (const Button *b : siblings) {
            any = any || b->isHovered();
        }
        decoration->setLightsHovered(any);
    });
    auto w = decoration->window();
    connect(w, &KDecoration3::DecoratedWindow::closeableChanged, this, [this]() {
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::minimizeableChanged, this, [this]() {
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, this, [this]() {
        update();
    });
}

Button::Button(QObject *parent, const QVariantList &args)
    : Button(args.at(0).value<KDecoration3::DecorationButtonType>(), args.at(1).value<Decoration *>(), parent)
{
}

Button *Button::create(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
{
    auto *d = qobject_cast<Decoration *>(decoration);
    if (!d) {
        return nullptr;
    }
    auto *button = new Button(type, d, parent);
    switch (type) {
    case KDecoration3::DecorationButtonType::Close:
        button->setEnabled(d->window()->isCloseable());
        QObject::connect(d->window(), &KDecoration3::DecoratedWindow::closeableChanged, button, &Button::setEnabled);
        break;
    case KDecoration3::DecorationButtonType::Minimize:
        button->setEnabled(d->window()->isMinimizeable());
        QObject::connect(d->window(), &KDecoration3::DecoratedWindow::minimizeableChanged, button, &Button::setEnabled);
        break;
    case KDecoration3::DecorationButtonType::Maximize:
        button->setEnabled(d->window()->isMaximizeable());
        QObject::connect(d->window(), &KDecoration3::DecoratedWindow::maximizeableChanged, button, &Button::setEnabled);
        break;
    default:
        button->setVisible(false);
        button->setGeometry(QRectF());
        break;
    }
    return button;
}

bool Button::isLight() const
{
    switch (type()) {
    case KDecoration3::DecorationButtonType::Close:
    case KDecoration3::DecorationButtonType::Minimize:
    case KDecoration3::DecorationButtonType::Maximize:
        return true;
    default:
        return false;
    }
}

QColor Button::fillColor(bool lit) const
{
    if (!lit || !isEnabled()) {
        return QColor(79, 79, 79);
    }
    switch (type()) {
    case KDecoration3::DecorationButtonType::Close:
        return QColor(255, 95, 87);
    case KDecoration3::DecorationButtonType::Minimize:
        return QColor(254, 188, 46);
    case KDecoration3::DecorationButtonType::Maximize:
        return QColor(40, 200, 64);
    default:
        return QColor(79, 79, 79);
    }
}

QColor Button::glyphColor() const
{
    switch (type()) {
    case KDecoration3::DecorationButtonType::Close:
        return QColor(77, 0, 0);
    case KDecoration3::DecorationButtonType::Minimize:
        return QColor(153, 88, 0);
    case KDecoration3::DecorationButtonType::Maximize:
        return QColor(0, 101, 0);
    default:
        return Qt::black;
    }
}

void Button::drawGlyph(QPainter *painter, const QRectF &rect) const
{
    const qreal unit = rect.width() / 14.0;
    QPen pen(glyphColor(), 1.6 * unit, Qt::SolidLine, Qt::RoundCap);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    const QPointF c = rect.center();
    switch (type()) {
    case KDecoration3::DecorationButtonType::Close: {
        const qreal arm = 2.6 * unit;
        painter->drawLine(QPointF(c.x() - arm, c.y() - arm), QPointF(c.x() + arm, c.y() + arm));
        painter->drawLine(QPointF(c.x() - arm, c.y() + arm), QPointF(c.x() + arm, c.y() - arm));
        break;
    }
    case KDecoration3::DecorationButtonType::Minimize: {
        const qreal arm = 3.6 * unit;
        painter->drawLine(QPointF(c.x() - arm, c.y()), QPointF(c.x() + arm, c.y()));
        break;
    }
    case KDecoration3::DecorationButtonType::Maximize: {
        // Two triangles pointing to opposite corners, the full-screen glyph.
        painter->setPen(Qt::NoPen);
        painter->setBrush(glyphColor());
        const qreal a = 3.4 * unit;
        const qreal gap = 0.7 * unit;
        QPainterPath upper;
        upper.moveTo(c.x() + a, c.y() - a);
        upper.lineTo(c.x() + a, c.y() + gap * 0.5 - 0.2 * unit);
        upper.lineTo(c.x() - gap * 0.5 + 0.2 * unit, c.y() - a);
        upper.closeSubpath();
        QPainterPath lower;
        lower.moveTo(c.x() - a, c.y() + a);
        lower.lineTo(c.x() - a, c.y() - gap * 0.5 + 0.2 * unit);
        lower.lineTo(c.x() + gap * 0.5 - 0.2 * unit, c.y() + a);
        lower.closeSubpath();
        painter->drawPath(upper);
        painter->drawPath(lower);
        break;
    }
    default:
        break;
    }
}

void Button::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    if (!decoration() || !isVisible() || !isLight()) {
        return;
    }
    auto *d = static_cast<Decoration *>(decoration());
    const bool lit = d->window()->isActive() || d->lightsHovered();
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    const QRectF rect = geometry();
    QColor fill = fillColor(lit);
    if (isPressed()) {
        fill = fill.darker(130);
    }
    painter->setPen(Qt::NoPen);
    painter->setBrush(fill);
    painter->drawEllipse(rect);
    painter->setPen(QPen(QColor(0, 0, 0, 48), rect.width() / 28.0));
    painter->setBrush(Qt::NoBrush);
    painter->drawEllipse(rect.adjusted(0.25, 0.25, -0.25, -0.25));
    if (d->lightsHovered() && isEnabled()) {
        drawGlyph(painter, rect);
    }
    painter->restore();
}

}
