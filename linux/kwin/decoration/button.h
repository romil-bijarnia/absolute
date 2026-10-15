// SPDX-License-Identifier: MIT
#pragma once

#include <KDecoration3/DecorationButton>

namespace Absolute
{
class Decoration;

// One of the three lights. Red, yellow and green when the window is active or the
// group is hovered, grey otherwise; the glyph shows while any light is hovered.
class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT
public:
    Button(KDecoration3::DecorationButtonType type, Decoration *decoration, QObject *parent = nullptr);
    explicit Button(QObject *parent, const QVariantList &args);

    static Button *create(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent);

    void paint(QPainter *painter, const QRectF &repaintArea) override;

private:
    bool isLight() const;
    QColor fillColor(bool lit) const;
    QColor glyphColor() const;
    void drawGlyph(QPainter *painter, const QRectF &rect) const;
};

}
