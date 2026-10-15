// SPDX-License-Identifier: MIT
#pragma once

#include "effect/effect.h"
#include "effect/effectwindow.h"
#include "effect/offscreeneffect.h"
#include "effect/timeline.h"

namespace KWin
{

struct GenieAnimation
{
    EffectWindowVisibleRef visibleRef;
    TimeLine timeLine;
};

// The Genie minimise as the macOS Dock performs it: a two-column funnel that forms in
// place, then slides the window body down a fixed profile into the tile. The window's
// target is the icon geometry the Dock publishes for it.
class GenieEffect : public OffscreenEffect
{
    Q_OBJECT

public:
    GenieEffect();

    void reconfigure(ReconfigureFlags) override;
    void prePaintScreen(ScreenPrePaintData &data) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;
    void postPaintScreen() override;
    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        return 50;
    }

    static bool supported();

protected:
    void apply(EffectWindow *window, int mask, WindowPaintData &data, WindowQuadList &quads) override;

private:
    void slotWindowAdded(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);
    void start(EffectWindow *w, bool minimising);

    std::chrono::milliseconds m_duration{500};
    QHash<EffectWindow *, GenieAnimation> m_animations;
};

} // namespace KWin
