// SPDX-License-Identifier: MIT
#pragma once

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationShadow>

#include <QVariantList>
#include <memory>

namespace KDecoration3
{
class DecorationButtonGroup;
}

namespace Absolute
{

// The Mac's window chrome, measured on macOS 27 with AppKit on 15 October 2026
// (linux/kwin/decoration/README.md): the numbers below are logical points.
namespace Metrics
{
constexpr qreal TitleBarHeight = 32;
constexpr qreal LightDiameter = 14;
constexpr qreal LightLeft = 9; // close light's left edge
constexpr qreal LightTop = 9;
constexpr qreal LightPitch = 23; // left edge to the next left edge
constexpr qreal CornerRadius = 16;
constexpr qreal ResizeBorder = 4; // invisible grab area outside the window
}

class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT
public:
    explicit Decoration(QObject *parent = nullptr, const QVariantList &args = QVariantList());
    ~Decoration() override;

    void paint(QPainter *painter, const QRectF &repaintArea) override;

    bool lightsHovered() const { return m_lightsHovered; }
    void setLightsHovered(bool hovered);
    bool isMaximized() const;

protected:
    bool init() override;

private:
    void recalculateGeometry();
    void updateShadow();
    QColor titleBarColor() const;
    QColor captionColor() const;

    KDecoration3::DecorationButtonGroup *m_lights = nullptr;
    bool m_lightsHovered = false;
};

}
