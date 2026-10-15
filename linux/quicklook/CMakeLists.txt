cmake_minimum_required(VERSION 3.20)
project(absolute-quicklook VERSION 0.1.0 LANGUAGES CXX)

# Absolute's Quick Look: a floating preview of the selected files (images, text,
# PDF, video, audio, anything else as its icon and details), closed with Space.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
include(GNUInstallDirs)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus)
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6CoreAddons REQUIRED)

qt_add_executable(absolute-quicklook
    src/main.cpp
    src/quicklook.cpp
    src/quicklook.h
    resources.qrc
)

target_link_libraries(absolute-quicklook PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus
    LayerShellQt::Interface
    KF6::WindowSystem
    KF6::KIOGui
    KF6::KIOWidgets
    KF6::CoreAddons
)

install(TARGETS absolute-quicklook RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
