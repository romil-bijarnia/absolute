cmake_minimum_required(VERSION 3.20)
project(absolute-decoration VERSION 0.1.0 LANGUAGES CXX)

# KWin window decoration drawn to the Mac's measured chrome: 32 pt titlebar, the
# three lights at 9/32/55 pt with glyphs on hover, 16 pt corners, soft shadow.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui)
find_package(KF6 REQUIRED COMPONENTS CoreAddons ColorScheme)
find_package(KDecoration3 REQUIRED)

add_library(absolutedecoration MODULE decoration.cpp button.cpp)
set_target_properties(absolutedecoration PROPERTIES OUTPUT_NAME org.absolute.decoration)
target_link_libraries(absolutedecoration PRIVATE KDecoration3::KDecoration KF6::CoreAddons KF6::ColorScheme)
install(TARGETS absolutedecoration DESTINATION ${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}/org.kde.kdecoration3)
