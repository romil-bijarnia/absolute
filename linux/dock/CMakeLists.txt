cmake_minimum_required(VERSION 3.20)
project(absolute-dock VERSION 0.1.0 LANGUAGES CXX)

# Absolute's Dock: a layer-shell window at the screen edge, driven by Plasma's task
# model, drawing the tiles with the magnification measured from macOS and publishing
# each tile's rectangle so KWin's Genie effect knows where a window minimises to.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus)
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)

qt_add_executable(absolute-dock
    src/main.cpp
    src/dock.cpp
    src/dock.h
    resources.qrc
)

target_link_libraries(absolute-dock PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus
    LayerShellQt::Interface
    KF6::WindowSystem
)

install(TARGETS absolute-dock RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/org.absolute.Dock.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
