# Selene - AI Agent Development Guide

> **Language**: This project uses **Chinese** for all documentation and comments. Please maintain this convention when
> modifying code.

## Project Overview

**Selene** is a cross-platform video player application based on MoonTV ("基于 MoonTV 的视频播放器"), built with
Flutter. It supports video streaming, live TV, search functionality, and user data management across multiple platforms.

- **Name**: selene
- **Version**: 1.6.6+2156
- **Flutter SDK**: >=3.4.3 <4.0.0
- **Package Manager**: pub (pubspec.yaml)

### Core Features

- Video playback with media_kit (cross-platform video player)
- Live TV streaming with EPG (Electronic Program Guide)
- Content search with multiple source aggregation
- User favorites and play history
- Dark/Light theme support (follows system by default)
- Multi-platform support: Android, iOS, macOS, Windows, Linux, Web
- DLNA casting support
- Picture-in-picture mode
- Local mode (subscription-based without server)

## Technology Stack

### Core Dependencies

| Category          | Package                                 | Purpose                           |
|-------------------|-----------------------------------------|-----------------------------------|
| State Management  | `provider`                              | Reactive state management         |
| Video Player      | `media_kit`                             | Cross-platform video playback     |
| Local Storage     | `hive`                                  | NoSQL local database              |
| HTTP Client       | `dio`, `http`                           | API communication                 |
| UI Icons          | `lucide_icons_flutter`, `flutter_svg`   | Iconography                       |
| Window Management | `bitsdojo_window`, `macos_window_utils` | Desktop window controls           |
| Downloads         | `gal`                                   | Media saving to gallery           |
| Casting           | `dlna_dart`                             | DLNA device discovery and casting |
| Brightness        | `screen_brightness`                     | Screen brightness control         |
| Volume            | `volume_controller`                     | System volume control             |

### Platform Support

- **Android**: minSdk 21, targetSdk latest, Kotlin DSL build scripts
- **iOS**: Standard Flutter iOS project, CocoaPods
- **macOS**: Custom window styling with macos_window_utils
- **Windows**: Custom window sizing with bitsdojo_window
- **Linux**: Standard Flutter Linux project
- **Web**: CanvasKit renderer

## Project Structure

```
lib/
├── main.dart                    # Application entry point
├── components/
│   └── animations/              # Custom animation widgets
├── design/                      # Design System 2026
│   ├── animations.dart          # Shared animations
│   ├── colors.dart              # Color palette (light/dark/glassmorphism)
│   ├── design_system.dart       # Library exports
│   ├── shadows.dart             # Shadow definitions
│   └── typography.dart          # Text styles
├── models/                      # Data models
│   ├── video_info.dart          # Video metadata
│   ├── play_record.dart         # Playback history
│   ├── favorite_item.dart       # User favorites
│   ├── search_result.dart       # Search results
│   ├── live_channel.dart        # Live TV channels
│   ├── live_source.dart         # Live TV sources
│   └── ...
├── screens/                     # Full-screen pages
│   ├── home_screen.dart         # Main screen with tabs
│   ├── player_screen.dart       # Video player
│   ├── search_screen.dart       # Search interface
│   ├── live_screen.dart         # Live TV browser
│   ├── live_player_screen.dart  # Live TV player
│   ├── login_screen.dart        # Authentication
│   ├── movie_screen.dart        # Movies category
│   ├── tv_screen.dart           # TV shows category
│   ├── anime_screen.dart        # Anime category
│   └── show_screen.dart         # Variety shows category
├── services/                    # Business logic
│   ├── api_service.dart         # HTTP API client
│   ├── theme_service.dart       # Theme management
│   ├── user_data_service.dart   # Local user data
│   ├── page_cache_service.dart  # Page data caching
│   ├── douban_service.dart      # Douban integration
│   ├── bangumi_service.dart     # Bangumi integration
│   ├── search_service.dart      # Search functionality
│   ├── live_service.dart        # Live TV streaming
│   ├── version_service.dart     # Update checking
│   └── ...
├── utils/                       # Utilities
│   ├── font_utils.dart          # Font helpers (Poppins/Microsoft YaHei)
│   ├── hive_adapters.dart       # Hive type adapters
│   ├── hive_initializer.dart    # Database initialization
│   └── http_overrides.dart      # SSL certificate handling
└── widgets/                     # Reusable UI components
    ├── video_card.dart          # Video thumbnail card
    ├── main_layout.dart         # App shell layout
    ├── player_controls/         # Platform-specific controls
    ├── hot_*_section.dart       # Content category sections
    └── ...
```

## Build Commands

### Development

```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Run with specific device
flutter run -d <device-id>

# Analyze code
flutter analyze

# Format code
dart format lib/
```

### Production Builds

The project includes a comprehensive build script (`build.sh`) for local builds:

```bash
# Build all platforms (parallel)
./build.sh

# Platform-specific builds
./build.sh --android-only       # Android APK (arm64, armv7)
./build.sh --ios-only           # iOS unsigned IPA
./build.sh --macos-only         # Both macOS architectures
./build.sh --macos-arm64-only   # Apple Silicon
./build.sh --macos-x86_64-only  # Intel Mac
./build.sh --apple-only         # iOS + macOS
./build.sh --sequential         # Sequential instead of parallel
```

### Manual Flutter Builds

```bash
# Android
flutter build apk --release --target-platform android-arm64,android-arm --split-per-abi
flutter build appbundle --release

# iOS (macOS only)
flutter build ios --release --no-codesign

# macOS (macOS only)
flutter build macos --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release

# Web
flutter build web --release --web-renderer canvaskit
```

## Coding Requirements

### Performance Standards

**新特性开发必须遵循高性能、低损耗原则：**

- **Widget 构建优化**
    - 使用 `const` 构造函数减少重建
    - 合理使用 `ListView.builder` 替代 `Column` 处理长列表
    - 避免在 `build` 方法中执行复杂计算
    - 使用 `RepaintBoundary` 隔离频繁重绘区域

- **状态管理优化**
    - 精确控制 `notifyListeners()` 调用时机
    - 使用 `Selector` 替代 `Consumer` 监听特定字段
    - 避免在 `didUpdateWidget` 中触发状态更新

- **资源管理**
    - 及时释放控制器（`VideoPlayerController`、`ScrollController` 等）
    - 使用 `CachedNetworkImage` 替代原生长图片加载
    - 图片使用适当分辨率，避免内存溢出

- **异步操作**
    - 使用 `FutureBuilder`/`StreamBuilder` 管理异步状态
    - 取消未完成的异步请求避免内存泄漏
    - 耗时操作移至 Isolate（如 JSON 解析、图片处理）

### Code Quality Gates

**每个开发阶段必须通过 `flutter analyze` 检查：**

```bash
# 阶段 1: 编码完成后立即检查
flutter analyze

# 阶段 2: 提交前最终检查
flutter analyze --fatal-infos --fatal-warnings
```

**检查规则：**

- ❌ 禁止提交包含 `error` 的代码
- ❌ 禁止提交包含 `warning` 的代码（特殊情况需注释说明）
- ⚠️ `info` 级别建议修复，可酌情处理

**自动修复命令：**

```bash
# 自动修复格式问题
dart fix --apply

# 格式化代码
dart format lib/
```

## Code Style Guidelines

### Language Conventions

- **Comments**: Use Chinese for all inline comments and documentation
- **Strings**: User-facing strings in Chinese, internal/debug strings can be English
- **Variable Names**: Use camelCase, descriptive English names
- **File Names**: snake_case for all Dart files

### Analysis Configuration (analysis_options.yaml)

The project uses strict analysis rules:

```yaml
# Key enforced rules
- always_declare_return_types: true      # Must declare return types
- always_use_package_imports: true       # No relative imports
- avoid_relative_lib_imports: true       # Package imports only
- prefer_final_fields: true              # Immutable where possible
- prefer_final_locals: true              # Final for local variables
- prefer_single_quotes: true             # Single quotes for strings
- use_key_in_widget_constructors: true   # Key parameter required
- use_build_context_synchronously: true  # Proper async context usage
```

### Design System Usage

Import the design system for consistent UI:

```dart
import 'package:selene/design/design_system.dart';

// Colors
AppColors.primary
AppColors.lightBackground
AppColors.darkSurface

// Glassmorphism
ColorUtils.glassmorphism(isDark: true)

// Theme extensions
Theme.of(context).colorScheme.surfaceColor
```

### Font Guidelines

Use the FontUtils for consistent typography:

```dart
import 'package:selene/utils/font_utils.dart';

// Primary font (Poppins on non-Windows, Microsoft YaHei on Windows)
Text('Hello', style: FontUtils.poppins(fontSize: 16))

// Monospace font
Text('Code', style: FontUtils.sourceCodePro(fontSize:14))
```

## Testing Instructions

### Current State

- **Unit Tests**: Minimal coverage (CI runs `flutter test` with `|| true`)
- **Widget Tests**: Not currently implemented
- **Integration Tests**: Not currently implemented

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Generate coverage report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
```

### CI/CD Testing

The GitHub Actions workflow runs:

1. Code analysis (`flutter analyze --fatal-infos --fatal-warnings`)
2. Formatting check (`dart format --set-exit-if-changed`)
3. Unit tests (`flutter test --coverage`)

## Security Considerations

### SSL/TLS Handling

The app globally disables certificate validation for development:

```dart
// lib/main.dart
HttpOverrides.global =

CustomizeHttpOverrides(); // Disables certificate checks
```

**Warning**: This is for development convenience. Production deployments should implement proper certificate pinning.

### Code Obfuscation

Release builds include code obfuscation:

```bash
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols
```

Debug symbols are uploaded as CI artifacts for crash analysis.

### Data Storage

- User credentials stored in Hive (local encrypted storage)
- Cookies managed by UserDataService
- No sensitive data logged in release builds

### Dependencies

CI includes a security audit step:

```bash
flutter pub audit  # Checks for known vulnerabilities
```

## Key Services Reference

### ApiService

Central HTTP client with automatic authentication:

```dart
// GET request
final response = await
ApiService.get<List<SearchResult>>
('/api/search',fromJson: (data) => /* parse logic */,);

// POST request
final response = await ApiService.post<void>(
'/api/favorites',
body: {'key': key, 'favorite': favoriteData},
);
```

### PageCacheService

Manages local caching for favorites, history, and search:

```dart

final cacheService = PageCacheService();
await cacheService.refreshFavorites(context);
await cacheService.refreshPlayRecords(context);
```

### ThemeService

Theme management via Provider:

```dart
// Toggle theme
context.read<ThemeService>().toggleTheme(context);

// Check current mode
final isDark = context.read<ThemeService>().isDarkMode;
```

## Local Development Mode

The app supports a "local mode" that works without a backend server:

1. User provides a subscription URL
2. App parses M3U/search sources from subscription
3. Content is fetched directly from source URLs

Enable via login screen -> "Local Mode" option.

## Common Tasks

### Adding a New Screen

1. Create file in `lib/screens/`
2. Add route navigation in relevant screen
3. Update imports to use package imports: `import 'package:selene/screens/new_screen.dart';`

### Adding a Model

1. Create model class in `lib/models/`
2. Add `fromJson`/`toJson` methods
3. Create Hive adapter in `lib/utils/hive_adapters.dart` if persistence needed
4. Register adapter in `lib/utils/hive_initializer.dart`

### Adding an API Endpoint

1. Add method to `ApiService` with proper generic typing
2. Return `ApiResponse<T>` with appropriate type
3. Handle 401 unauthorized in `_handleResponse`

## Troubleshooting

### Build Issues

```bash
# Clean build artifacts
flutter clean
rm -rf build/ ios-build/ build-arm64/ build-x86_64/

# Regenerate platform files
flutter pub get
```

### Dependency Issues

```bash
# Update dependencies
flutter pub upgrade

# Check for outdated packages
flutter pub outdated
```

### Platform-Specific

**Android**: Ensure Java 17 is installed and `JAVA_HOME` is set
**iOS/macOS**: Requires Xcode, run `pod install` in ios/ directory
**Windows**: Requires Visual Studio with C++ desktop development
**Linux**: Requires clang, cmake, ninja-build, GTK development headers

## CI/CD Pipeline

GitHub Actions workflows:

- **ci-cd.yml**: Full pipeline on push to main/develop/release branches
    - Code analysis and testing
    - Security audit
    - Parallel builds for all 6 platforms
    - Automatic release creation on tags

- **pr-check.yml**: Lightweight validation on pull requests
    - Analysis and formatting checks
    - Smoke build test

Build matrix: Android (APK + AAB), iOS (IPA), macOS (ARM64 + x86_64 DMG), Windows (ZIP), Linux (tar.gz), Web (tar.gz)

## Dependencies Overview

### SDK & Framework

| Package     | Version | Description          |
|-------------|---------|----------------------|
| Flutter SDK | 3.41.2  | UI framework         |
| Dart SDK    | 3.11.0  | Programming language |

### Core Dependencies

| Package                | Version | Purpose         |
|------------------------|---------|-----------------|
| `provider`             | 6.1.5+1 | 状态管理            |
| `media_kit`            | 1.2.6   | 跨平台视频播放         |
| `media_kit_video`      | 2.0.1   | 视频播放器 UI        |
| `media_kit_libs_video` | 1.0.7   | 视频播放原生库         |
| `hive`                 | 2.2.3   | NoSQL 本地数据库     |
| `hive_flutter`         | 1.1.0   | Hive Flutter 集成 |
| `dio`                  | 5.9.1   | 强大的 HTTP 客户端    |
| `http`                 | 1.6.0   | 标准 HTTP 客户端     |

### UI & Design

| Package                | Version | Purpose    |
|------------------------|---------|------------|
| `flutter_svg`          | 2.2.3   | SVG 图片支持   |
| `lucide_icons_flutter` | 3.1.10  | Lucide 图标库 |
| `google_fonts`         | 8.0.2   | Google 字体  |
| `cupertino_icons`      | 1.0.8   | iOS 风格图标   |
| `cached_network_image` | 3.4.1   | 图片缓存加载     |

### Platform & Device

| Package              | Version | Purpose      |
|----------------------|---------|--------------|
| `bitsdojo_window`    | 0.1.6   | Windows 窗口控制 |
| `macos_window_utils` | 1.9.1   | macOS 窗口工具   |
| `screen_brightness`  | 2.1.7   | 屏幕亮度控制       |
| `volume_controller`  | 3.4.2   | 系统音量控制       |
| `wakelock_plus`      | 1.4.0   | 保持屏幕常亮       |
| `gal`                | 2.3.2   | 保存媒体到相册      |
| `path_provider`      | 2.1.5   | 获取系统路径       |
| `package_info_plus`  | 9.0.0   | 应用信息获取       |
| `url_launcher`       | 6.3.2   | 外部链接启动       |
| `file_selector`      | 1.1.0   | 文件选择器        |

### Network & Data

| Package              | Version | Purpose      |
|----------------------|---------|--------------|
| `web_socket_channel` | 3.0.3   | WebSocket 通信 |
| `xml`                | 6.6.1   | XML 解析       |
| `encrypt`            | 5.0.3   | 加密解密         |
| `crypto`             | 3.0.7   | 哈希算法         |
| `dlna_dart`          | 0.1.0   | DLNA 投屏      |

### Utilities

| Package                      | Version | Purpose     |
|------------------------------|---------|-------------|
| `intl`                       | 0.20.2  | 国际化与格式化     |
| `uuid`                       | 4.5.3   | UUID 生成     |
| `flutter_cache_manager`      | 3.4.1   | 缓存管理        |
| `scrollable_positioned_list` | 0.3.8   | 可定位滚动列表     |
| `gpt_markdown`               | 1.1.5   | Markdown 渲染 |
| `bs58check`                  | 1.0.2   | Base58 编码校验 |
| `gbk_codec`                  | 0.4.0   | GBK 编码支持    |

### Development & Testing

| Package                  | Version | Purpose    |
|--------------------------|---------|------------|
| `flutter_lints`          | 6.0.0   | 官方 Lint 规则 |
| `flutter_test`           | (sdk)   | 测试框架       |
| `flutter_launcher_icons` | 0.14.4  | 应用图标生成     |

### Dependency Graph Summary

```
selene
├── Core: provider, media_kit*, hive*, dio
├── UI: flutter_svg, lucide_icons_flutter, google_fonts, cached_network_image
├── Platform: bitsdojo_window, macos_window_utils, screen_brightness, volume_controller
├── Network: http, web_socket_channel, xml, dlna_dart
├── Crypto: encrypt, crypto, bs58check
└── Utils: intl, uuid, path_provider, package_info_plus, url_launcher
```
