// SPDX-License-Identifier: MIT
#include "genie.h"

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(GenieEffect,
                              "metadata.json",
                              return GenieEffect::supported();)

} // namespace KWin

#include "main.moc"
