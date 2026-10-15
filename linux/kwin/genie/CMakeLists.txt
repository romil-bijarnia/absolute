cmake_minimum_required(VERSION 3.20)
project(absolute-genie VERSION 0.1.0 LANGUAGES CXX)

# KWin effect: minimises windows into the Dock with the Genie recovered from
# macOS 27's Dock (research/DOCK-MINIMISE.md), replacing Magic Lamp.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus Quick)
find_package(KF6 REQUIRED COMPONENTS CoreAddons Config)
find_package(KWin REQUIRED)

add_library(absolute_genie MODULE genie.cpp main.cpp)
target_link_libraries(absolute_genie PRIVATE KWin::kwin KF6::ConfigCore KF6::CoreAddons)
install(TARGETS absolute_genie DESTINATION ${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}/kwin/effects/plugins)
