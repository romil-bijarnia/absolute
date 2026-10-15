cmake_minimum_required(VERSION 3.20)
project(absolute-spotlight VERSION 0.1.0 LANGUAGES CXX)

# Absolute's Spotlight: the centred search panel, drawn by Absolute on Plasma's
# search backend (milou / KRunner), toggled by Meta+Space over DBus.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus)
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)

qt_add_executable(absolute-spotlight
    src/main.cpp
    src/spotlight.cpp
    src/spotlight.h
    resources.qrc
)

target_link_libraries(absolute-spotlight PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus
    LayerShellQt::Interface
    KF6::WindowSystem
)

install(TARGETS absolute-spotlight RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
