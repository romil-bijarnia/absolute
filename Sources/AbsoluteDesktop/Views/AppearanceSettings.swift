import SwiftUI
import AbsoluteCore

struct AppearanceSettings: View {
    @Bindable var desktop: DesktopStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Desktop appearance").font(.title2).fontWeight(.semibold)
            Text("Choose your wallpaper.").foregroundStyle(.secondary)
            HStack(spacing: 15) {
                ForEach(Wallpaper.allCases) { wallpaper in
                    Button { desktop.wallpaper = wallpaper } label: {
                        VStack(spacing: 8) {
                            WallpaperView(wallpaper: wallpaper).frame(width: 140, height: 95)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(desktop.wallpaper == wallpaper ? Color.accentColor : .clear, lineWidth: 3) }
                            Text(wallpaper.title).font(.system(size: 13))
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(wallpaper.title) wallpaper")
                }
            }
        }.padding(30).frame(width: 520)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 60)).foregroundStyle(Color.cyan.gradient)
            Text("Absolute").font(.system(size: 31, weight: .semibold))
            Text("Your desktop. Your system.").font(.system(size: 14)).foregroundStyle(.secondary)
            Text("Desktop Preview 0.2").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
