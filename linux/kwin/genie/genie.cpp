// SPDX-License-Identifier: MIT
#include "genie.h"
#include "effect/effecthandler.h"

#include <QEasingCurve>
#include <KConfigGroup>
#include <KSharedConfig>
#include <algorithm>
#include <cmath>

using namespace std::chrono_literals;

namespace KWin
{

namespace
{

// The Dock's step budget for a distance: floor(ln(d / 2 + 1)) * 50.
double steps(double distance)
{
    return std::floor(std::log(std::abs(distance) * 0.5 + 1.0)) * 50.0;
}

double ramp(double value)
{
    return 0.5 - 0.5 * std::cos(M_PI * value);
}

enum class Direction {
    Down, // dock below the window
    Up,
    Left,
    Right,
};

// Canonical frame: the dock lies toward decreasing `along`. Screen coordinates grow
// downward on screen, so a bottom dock means along = -y.
struct Frame
{
    Direction direction;

    double along(double x, double y) const
    {
        switch (direction) {
        case Direction::Down:
            return -y;
        case Direction::Up:
            return y;
        case Direction::Left:
            return x;
        case Direction::Right:
            return -x;
        }
        return -y;
    }
    double across(double x, double y) const
    {
        return (direction == Direction::Down || direction == Direction::Up) ? x : y;
    }
    // Back to screen coordinates.
    void screen(double along, double across, double &x, double &y) const
    {
        switch (direction) {
        case Direction::Down:
            x = across;
            y = -along;
            return;
        case Direction::Up:
            x = across;
            y = along;
            return;
        case Direction::Left:
            x = along;
            y = across;
            return;
        case Direction::Right:
            x = -along;
            y = across;
            return;
        }
    }
    struct Box
    {
        double minAlong, maxAlong, minAcross, maxAcross;
        double length() const { return maxAlong - minAlong; }
        double breadth() const { return maxAcross - minAcross; }
    };
    Box box(const RectF &rect) const
    {
        const double a1 = along(rect.x(), rect.y());
        const double a2 = along(rect.x() + rect.width(), rect.y() + rect.height());
        const double c1 = across(rect.x(), rect.y());
        const double c2 = across(rect.x() + rect.width(), rect.y() + rect.height());
        return Box{std::min(a1, a2), std::max(a1, a2), std::min(c1, c2), std::max(c1, c2)};
    }
};

} // namespace

GenieEffect::GenieEffect()
{
    reconfigure(ReconfigureAll);
    connect(effects, &EffectsHandler::windowAdded, this, &GenieEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &GenieEffect::slotWindowDeleted);
    const auto windows = effects->stackingOrder();
    for (EffectWindow *window : windows) {
        slotWindowAdded(window);
    }
    setVertexSnappingMode(RenderGeometry::VertexSnappingMode::None);
}

bool GenieEffect::supported()
{
    // Magic Lamp also requires effects->animationsSupported(), which KWin denies on
    // software rendering. The Genie runs there too (a virtual machine without a GPU),
    // slower but correct, so only OpenGL compositing is required.
    return OffscreenEffect::supported();
}

void GenieEffect::reconfigure(ReconfigureFlags)
{
    // DockBar::effectDur for the Genie: 500 ms, scaled by the global animation speed.
    // kwinrc [Effect-absolute_genie] Duration overrides it (milliseconds).
    const KConfigGroup group = effects->config()->group(QStringLiteral("Effect-absolute_genie"));
    const int configured = group.readEntry(QStringLiteral("Duration"), 500);
    m_duration = animationTime(std::chrono::milliseconds(configured > 0 ? configured : 500));
}

void GenieEffect::prePaintScreen(ScreenPrePaintData &data)
{
    data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;
    effects->prePaintScreen(data);
}

void GenieEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
{
    auto animationIt = m_animations.find(w);
    if (animationIt != m_animations.end()) {
        (*animationIt).timeLine.advance(view);
        data.setTransformed();
    }
    effects->prePaintWindow(view, w, data);
}

void GenieEffect::apply(EffectWindow *w, int mask, WindowPaintData &data, WindowQuadList &quads)
{
    auto animationIt = m_animations.constFind(w);
    if (animationIt == m_animations.constEnd()) {
        return;
    }
    // The timeline's easing is the Dock's cosine clock, so this is the transition value.
    const double progress = (*animationIt).timeLine.value();

    const RectF geo = w->frameGeometry();
    RectF icon = w->iconGeometry();
    const RectF screen = effects->clientArea(ScreenArea, w);
    if (!icon.isValid() || icon.width() <= 0 || icon.height() <= 0) {
        // No tile published: aim at the bottom centre of the screen.
        icon = RectF(screen.x() + screen.width() / 2 - 24, screen.y() + screen.height() - 48, 48, 48);
    }

    Direction direction = Direction::Down;
    const double iconCentreY = icon.y() + icon.height() / 2;
    const double iconCentreX = icon.x() + icon.width() / 2;
    const double gapBottom = screen.y() + screen.height() - iconCentreY;
    const double gapTop = iconCentreY - screen.y();
    const double gapLeft = iconCentreX - screen.x();
    const double gapRight = screen.x() + screen.width() - iconCentreX;
    const double smallest = std::min({gapBottom, gapTop, gapLeft, gapRight});
    if (smallest == gapTop) {
        direction = Direction::Up;
    } else if (smallest == gapLeft) {
        direction = Direction::Left;
    } else if (smallest == gapRight) {
        direction = Direction::Right;
    }

    const Frame frame{direction};
    const Frame::Box win = frame.box(geo);
    const Frame::Box tile = frame.box(icon);

    // The model, as DockMinimise.genie() computes it.
    const double leading = tile.minAcross - win.minAcross;
    const double trailing = tile.maxAcross - win.maxAcross;
    const double overlap = std::max(0.0, tile.maxAlong - win.minAlong);
    const double travel = overlap > 0 ? -win.length() : tile.maxAlong - win.maxAlong;
    const double distance = std::abs(travel);

    double squeezeBudget = steps(std::max(2 * overlap, (std::abs(leading) + std::abs(trailing)) * 0.125));
    const double slideBudget = steps(distance);
    const double entryArgument = distance > 0 ? 1 - 2 * std::abs(travel + win.length()) / distance : 1;
    const double entryStep = slideBudget * std::acos(std::clamp(entryArgument, -1.0, 1.0)) / M_PI;
    double lead = 0;
    if (squeezeBudget > entryStep) {
        lead = squeezeBudget - entryStep;
    } else {
        squeezeBudget = entryStep;
    }
    const double total = (slideBudget + lead) * progress;
    const double squeezeStep = std::clamp(total, 0.0, squeezeBudget);
    const double slideStep = std::clamp(total - lead, 0.0, slideBudget);
    const double squeeze = squeezeBudget > 0 ? ramp(squeezeStep / squeezeBudget) : 1;
    const double slide = slideBudget > 0 ? ramp(slideStep / slideBudget) : 1;

    const double leadingSqueezed = leading * squeeze;
    const double trailingSqueezed = trailing * squeeze;
    const double centre = win.maxAlong + overlap * squeeze;
    const double far = centre + travel * slide;
    const double naturalNear = far - win.length();
    const double anchor = slide > 0 ? std::max(naturalNear, tile.maxAlong) : naturalNear;
    const double span = double(int(travel + 0.5));
    double lowest = anchor;
    if (std::abs(travel + win.length()) < std::abs(travel * slide)) {
        lowest = std::max(naturalNear, tile.minAlong);
    }
    const double extent = far - lowest;

    const auto factorAt = [&](double along) {
        if (along < anchor) {
            return 1.0; // inside the tile: fully squeezed
        }
        if (span == 0) {
            return 1.0;
        }
        return ramp(std::clamp((along - centre) / span, 0.0, 1.0));
    };

    quads = quads.makeGrid(24);
    for (WindowQuad &quad : quads) {
        for (int i = 0; i < 4; ++i) {
            WindowVertex &vertex = quad[i];
            const double sx = geo.x() + vertex.x();
            const double sy = geo.y() + vertex.y();
            const double alongS = frame.along(sx, sy);
            const double acrossS = frame.across(sx, sy);
            const double fraction = win.length() > 0 ? std::clamp((win.maxAlong - alongS) / win.length(), 0.0, 1.0) : 0.0;
            const double along = far - fraction * extent;
            const double factor = factorAt(along);
            const double leftEdge = win.minAcross + leadingSqueezed * factor;
            const double rightEdge = win.maxAcross + trailingSqueezed * factor;
            const double acrossFraction = win.breadth() > 0 ? (acrossS - win.minAcross) / win.breadth() : 0.0;
            const double across = leftEdge + acrossFraction * (rightEdge - leftEdge);
            double nx = 0, ny = 0;
            frame.screen(along, across, nx, ny);
            vertex.move(nx - geo.x(), ny - geo.y());
        }
    }
}

void GenieEffect::postPaintScreen()
{
    auto animationIt = m_animations.begin();
    while (animationIt != m_animations.end()) {
        if ((*animationIt).timeLine.done()) {
            unredirect(animationIt.key());
            animationIt = m_animations.erase(animationIt);
        } else {
            ++animationIt;
        }
    }
    effects->addRepaintFull();
    effects->postPaintScreen();
}

void GenieEffect::slotWindowAdded(EffectWindow *w)
{
    connect(w, &EffectWindow::minimizedChanged, this, [this, w]() {
        start(w, w->isMinimized());
    });
}

void GenieEffect::slotWindowDeleted(EffectWindow *w)
{
    m_animations.remove(w);
}

void GenieEffect::start(EffectWindow *w, bool minimising)
{
    if (effects->activeFullScreenEffect()) {
        return;
    }
    GenieAnimation &animation = m_animations[w];
    if (animation.timeLine.running()) {
        animation.timeLine.toggleDirection();
    } else {
        animation.visibleRef = EffectWindowVisibleRef(w, EffectWindow::PAINT_DISABLED_BY_MINIMIZE);
        animation.timeLine.setDirection(minimising ? TimeLine::Forward : TimeLine::Backward);
        animation.timeLine.setDuration(m_duration);
        animation.timeLine.setEasingCurve(QEasingCurve::InOutSine);
    }
    redirect(w);
    effects->addRepaintFull();
}

bool GenieEffect::isActive() const
{
    return !m_animations.isEmpty();
}

} // namespace KWin

#include "moc_genie.cpp"
