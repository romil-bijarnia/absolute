cmake_minimum_required(VERSION 3.20)
project(absolute-launchpad VERSION 0.1.0 LANGUAGES CXX)

# Absolute's Launchpad: the full-screen paged grid of applications over a blurred
# desktop, with search, toggled from the Dock, F4 or DBus.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus)
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Service REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6CoreAddons REQUIRED)

qt_add_executable(absolute-launchpad
    src/main.cpp
    src/launchpad.cpp
    src/launchpad.h
    resources.qrc
)

target_link_libraries(absolute-launchpad PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus
    LayerShellQt::Interface
    KF6::WindowSystem
    KF6::Service
    KF6::KIOGui
    KF6::CoreAddons
)

install(TARGETS absolute-launchpad RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
