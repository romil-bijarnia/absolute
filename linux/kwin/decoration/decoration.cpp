// SPDX-License-Identifier: MIT
#include "decoration.h"
#include "button.h"

#include <KColorScheme>
#include <KDecoration3/DecorationButtonGroup>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/ScaleHelpers>
#include <KPluginFactory>

#include <QFontMetricsF>
#include <QImage>
#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>
#include <vector>

K_PLUGIN_FACTORY_WITH_JSON(AbsoluteDecorationFactory, "absolute.json", registerPlugin<Absolute::Decoration>(); registerPlugin<Absolute::Button>();)

namespace Absolute
{

namespace
{

// Three box blurs approximate a Gaussian; only the alpha channel carries the shadow.
void blurAlpha(QImage &image, int radius)
{
    if (radius < 1) {
        return;
    }
    const int w = image.width();
    const int h = image.height();
    std::vector<int> alpha(w * h);
    for (int y = 0; y < h; ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            alpha[y * w + x] = qAlpha(line[x]);
        }
    }
    std::vector<int> tmp(w * h);
    for (int pass = 0; pass < 3; ++pass) {
        for (int y = 0; y < h; ++y) {
            int sum = 0;
            for (int x = -radius; x <= radius; ++x) {
                sum += alpha[y * w + std::clamp(x, 0, w - 1)];
            }
            for (int x = 0; x < w; ++x) {
                tmp[y * w + x] = sum / (2 * radius + 1);
                sum += alpha[y * w + std::clamp(x + radius + 1, 0, w - 1)] - alpha[y * w + std::clamp(x - radius, 0, w - 1)];
            }
        }
        for (int x = 0; x < w; ++x) {
            int sum = 0;
            for (int y = -radius; y <= radius; ++y) {
                sum += tmp[std::clamp(y, 0, h - 1) * w + x];
            }
            for (int y = 0; y < h; ++y) {
                alpha[y * w + x] = sum / (2 * radius + 1);
                sum += tmp[std::clamp(y + radius + 1, 0, h - 1) * w + x] - tmp[std::clamp(y - radius, 0, h - 1) * w + x];
            }
        }
    }
    for (int y = 0; y < h; ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < w; ++x) {
            const int a = alpha[y * w + x];
            line[x] = qRgba(0, 0, 0, a);
        }
    }
}

// A nine-slice shadow texture around a rounded square the size of two corners.
std::shared_ptr<KDecoration3::DecorationShadow> makeShadow(qreal cornerRadius, int blur, int offsetY, qreal strength)
{
    const int r = std::max(1, int(std::lround(cornerRadius)));
    const int pad = blur * 3 + offsetY;
    const int box = 2 * r + 1;
    const int size = box + 2 * pad;
    QImage image(size, size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(Qt::NoPen);
    painter.setBrush(QColor(0, 0, 0, int(255 * strength)));
    painter.drawRoundedRect(QRectF(pad, pad + offsetY, box, box), r, r);
    painter.end();
    blurAlpha(image, blur);
    // Nothing of the shadow may show through the window's own area.
    QPainter clear(&image);
    clear.setCompositionMode(QPainter::CompositionMode_Source);
    clear.setRenderHint(QPainter::Antialiasing);
    clear.setPen(Qt::NoPen);
    clear.setBrush(Qt::transparent);
    clear.drawRoundedRect(QRectF(pad, pad, box, box), r, r);
    clear.end();
    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    shadow->setPadding(QMargins(pad, pad, pad, pad));
    shadow->setInnerShadowRect(QRectF(QPointF(pad + r, pad + r), QSizeF(1, 1)));
    shadow->setShadow(image);
    return shadow;
}

}

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

Decoration::~Decoration() = default;

bool Decoration::isMaximized() const
{
    return window()->isMaximized() && settings()->isAlphaChannelSupported() == false ? true : window()->isMaximized();
}

bool Decoration::init()
{
    auto w = window();
    auto s = settings();
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, &Decoration::recalculateGeometry);
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, &Decoration::recalculateGeometry);
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::recalculateGeometry);
    connect(w, &KDecoration3::DecoratedWindow::nextScaleChanged, this, &Decoration::recalculateGeometry);
    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, [this]() {
        updateShadow();
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, [this]() {
        update(titleBar());
    });
    connect(w, &KDecoration3::DecoratedWindow::paletteChanged, this, [this]() {
        update();
    });
    connect(s.get(), &KDecoration3::DecorationSettings::fontChanged, this, [this]() {
        update(titleBar());
    });
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, &Decoration::recalculateGeometry);

    m_lights = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, &Button::create);
    recalculateGeometry();
    updateShadow();
    return true;
}

void Decoration::setLightsHovered(bool hovered)
{
    if (m_lightsHovered == hovered) {
        return;
    }
    m_lightsHovered = hovered;
    update(titleBar());
}

void Decoration::recalculateGeometry()
{
    const qreal scale = window()->nextScale();
    const qreal titleHeight = KDecoration3::snapToPixelGrid(Metrics::TitleBarHeight, scale);
    const bool maximized = window()->isMaximized();
    setBorders(QMarginsF(0, titleHeight, 0, 0));
    const qreal grab = maximized ? 0 : KDecoration3::snapToPixelGrid(Metrics::ResizeBorder, scale);
    setResizeOnlyBorders(QMarginsF(grab, 0, grab, grab));
    setTitleBar(QRectF(0, 0, window()->width(), titleHeight));
    const qreal radius = maximized ? 0 : Metrics::CornerRadius;
    setBorderRadius(KDecoration3::BorderRadius(radius));
    setOpaque(maximized);

    const qreal diameter = KDecoration3::snapToPixelGrid(Metrics::LightDiameter, scale);
    const qreal pitch = KDecoration3::snapToPixelGrid(Metrics::LightPitch, scale);
    m_lights->setSpacing(pitch - diameter);
    const auto buttons = m_lights->buttons();
    for (auto *button : buttons) {
        if (button->isVisible()) {
            button->setGeometry(QRectF(QPointF(0, 0), QSizeF(diameter, diameter)));
        }
    }
    m_lights->setPos(QPointF(KDecoration3::snapToPixelGrid(Metrics::LightLeft, scale), KDecoration3::snapToPixelGrid(Metrics::LightTop, scale)));
    update();
}

void Decoration::updateShadow()
{
    // Active windows carry the Mac's wide soft shadow, inactive ones a tighter one.
    static std::shared_ptr<KDecoration3::DecorationShadow> active;
    static std::shared_ptr<KDecoration3::DecorationShadow> inactive;
    if (!active) {
        active = makeShadow(Metrics::CornerRadius, 18, 12, 0.62);
        inactive = makeShadow(Metrics::CornerRadius, 9, 5, 0.42);
    }
    setShadow(window()->isActive() ? active : inactive);
}

QColor Decoration::titleBarColor() const
{
    const KColorScheme scheme(window()->isActive() ? QPalette::Active : QPalette::Inactive, KColorScheme::Header);
    return scheme.background().color();
}

QColor Decoration::captionColor() const
{
    const KColorScheme scheme(window()->isActive() ? QPalette::Active : QPalette::Inactive, KColorScheme::Header);
    QColor color = scheme.foreground().color();
    if (!window()->isActive()) {
        color.setAlphaF(0.5);
    }
    return color;
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    const QRectF bar = titleBar();
    const qreal radius = window()->isMaximized() ? 0 : Metrics::CornerRadius;
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);
    painter->setBrush(titleBarColor());
    QPainterPath path;
    path.addRoundedRect(QRectF(bar.x(), bar.y(), bar.width(), bar.height() + radius), radius, radius);
    painter->setClipRect(bar);
    painter->drawPath(path);
    painter->setClipping(false);

    // Caption centred across the window, kept clear of the lights.
    QFont font = settings()->font();
    font.setWeight(QFont::DemiBold);
    painter->setFont(font);
    painter->setPen(captionColor());
    const qreal lightsRight = m_lights->geometry().right() + 10;
    const qreal margin = std::max(lightsRight, qreal(12));
    const QRectF captionRect(margin, bar.y(), bar.width() - 2 * margin, bar.height());
    const QFontMetricsF metrics(font);
    const QString caption = metrics.elidedText(window()->caption(), Qt::ElideMiddle, captionRect.width());
    painter->drawText(captionRect, Qt::AlignCenter | Qt::TextSingleLine, caption);
    painter->restore();

    m_lights->paint(painter, repaintArea);
}

}

#include "decoration.moc"
