# Selene 构建与运行指南

> **语言**: 中文 | **版本**: 1.6.6+2156 | **Flutter SDK**: >=3.4.3 <4.0.0

---

## ⚡ 快速参考 - 生产打包命令

### 常用命令速查表

| 平台                | 命令                                                                  | 输出文件                        |
|-------------------|---------------------------------------------------------------------|-----------------------------|
| **Android (APK)** | `flutter build apk --release --split-per-abi --no-tree-shake-icons` | `app-arm64-v8a-release.apk` |
| **Android (AAB)** | `flutter build appbundle --release --no-tree-shake-icons`           | `app-release.aab`           |
| **iOS**           | `flutter build ios --release --no-codesign`                         | `Runner.app` → `.ipa`       |
| **macOS**         | `flutter build macos --release`                                     | `selene.app`                |
| **Windows**       | `flutter build windows --release`                                   | `Release/` 文件夹              |
| **Linux**         | `flutter build linux --release`                                     | `bundle/` 文件夹               |
| **Web**           | `flutter build web --release --web-renderer canvaskit`              | `web/` 文件夹                  |
| **一键全端**          | `./build.sh`                                                        | `dist/` 文件夹                 |

### 详细生产命令

#### 🤖 Android

```bash
# 快速测试（仅 arm64，约 20-30s）
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons

# 生产分包（推荐，生成 2-3 个 APK）
flutter build apk --release --split-per-abi --no-tree-shake-icons

# Google Play 上架（AAB 格式）
flutter build appbundle --release --no-tree-shake-icons
```

#### 🍎 iOS（仅 macOS）

```bash
# 无签名 IPA（CI/测试）
flutter build ios --release --no-codesign

# 签名发布版本
flutter build ios --release
```

#### 🖥️ macOS（仅 macOS）

```bash
# ARM64 (Apple Silicon)
flutter build macos --release --dart-define=FLUTTER_TARGET_PLATFORM=darwin-arm64

# x86_64 (Intel)
flutter build macos --release --dart-define=FLUTTER_TARGET_PLATFORM=darwin-x64
```

#### 🪟 Windows（仅 Windows）

```bash
flutter build windows --release
```

#### 🐧 Linux（仅 Linux）

```bash
flutter build linux --release
```

#### 🌐 Web

```bash
# CanvasKit 渲染（推荐，性能好）
flutter build web --release --web-renderer canvaskit

# HTML 渲染（体积小）
flutter build web --release --web-renderer html
```

---

## 📋 目录

1. [环境要求](#环境要求)
2. [项目初始化](#项目初始化)
3. [开发运行](#开发运行)
4. [生产打包](#生产打包)
5. [平台特定说明](#平台特定说明)
6. [常见问题](#常见问题)

---

## 🔧 环境要求

### 必需环境

| 工具          | 版本要求            | 说明                     |
|-------------|-----------------|------------------------|
| Flutter SDK | >=3.4.3, <4.0.0 | 运行 `flutter doctor` 检查 |
| Dart SDK    | >=3.4.3         | 随 Flutter 一起安装         |
| Android SDK | API 36          | 编译 Android 必需          |
| Java JDK    | 17              | 统一使用 JDK 17            |
| Gradle      | 9.3.1           | 由 wrapper 自动管理         |

### 平台特定要求

| 目标平台    | 操作系统要求              | 额外工具                              |
|---------|---------------------|-----------------------------------|
| Android | Windows/macOS/Linux | Android Studio, NDK 29.0.14206865 |
| iOS     | macOS only          | Xcode 15+, CocoaPods              |
| macOS   | macOS only          | Xcode 15+                         |
| Windows | Windows only        | Visual Studio 2022 (C++ 桌面开发)     |
| Linux   | Linux only          | clang, cmake, ninja-build, GTK    |
| Web     | 任意                  | Chrome 浏览器                        |

---

## 🚀 项目初始化

### 1. 克隆项目后首次设置

```bash
# 进入项目目录
cd Selene-Source

# 获取依赖
flutter pub get

# 验证环境
flutter doctor
```

### 2. 代码生成（如有需要）

```bash
# 生成 Flutter 本地化文件
flutter gen-l10n

# 生成应用图标
flutter pub run flutter_launcher_icons:main
```

---

## 💻 开发运行

### 查看可用设备

```bash
flutter devices
```

### 运行调试版本

```bash
# 运行到第一个可用设备
flutter run

# 运行到指定设备（通过设备 ID）
flutter run -d <device-id>

# 运行并启用热重载（默认已启用）
flutter run --hot

# 运行发布模式（测试性能）
flutter run --release

# 运行 Profile 模式（性能分析）
flutter run --profile
```

### Android 开发

```bash
# 连接安卓设备或启动模拟器后
flutter run -d android

# 指定 Android 设备
flutter run -d <android-device-id>

# 查看日志
flutter logs
```

### iOS 开发（仅 macOS）

```bash
# 运行到 iOS 模拟器
flutter run -d ios

# 运行到真机（需配置签名）
flutter run -d <ios-device-id>
```

### macOS 开发（仅 macOS）

```bash
# 运行 macOS 桌面版
flutter run -d macos
```

### Windows 开发（仅 Windows）

```bash
# 运行 Windows 桌面版
flutter run -d windows
```

### Linux 开发（仅 Linux）

```bash
# 运行 Linux 桌面版
flutter run -d linux
```

### Web 开发

```bash
# 运行 Web 版（CanvasKit 渲染器，推荐）
flutter run -d chrome --web-renderer canvaskit

# 运行 Web 版（HTML 渲染器）
flutter run -d chrome --web-renderer html

# 指定端口运行
flutter run -d chrome --web-port 8080
```

---

## 📦 生产打包

### 快速打包脚本（推荐）

项目根目录提供了 `build.sh` 脚本，支持一键打包所有平台：

```bash
# 赋予执行权限（首次使用）
chmod +x build.sh

# 构建所有平台（并行）
./build.sh

# 仅构建 Android
./build.sh --android-only

# 仅构建 iOS（仅 macOS）
./build.sh --ios-only

# 仅构建 macOS（双架构，仅 macOS）
./build.sh --macos-only

# 仅构建 macOS ARM64
./build.sh --macos-arm64-only

# 仅构建 macOS x86_64
./build.sh --macos-x86_64-only

# 构建所有 Apple 平台
./build.sh --apple-only

# 顺序构建（非并行）
./build.sh --sequential

# 查看帮助
./build.sh --help
```

---

## 🤖 Android 打包

### 开发测试包

```bash
# 快速构建（仅 arm64-v8a，约 20-30s）
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons

# 构建多架构 APK（单个文件，包含所有 ABI）
flutter build apk --release --no-tree-shake-icons
```

### 生产发布包

```bash
# 分架构 APK（推荐，文件更小）
flutter build apk --release \
    --target-platform android-arm64,android-arm \
    --split-per-abi \
    --no-tree-shake-icons

# 输出文件：
# - app-arm64-v8a-release.apk (约 38MB)
# - app-armeabi-v7a-release.apk (约 36MB)
# - app-x86_64-release.apk (约 42MB)
```

### Google Play 上架包（AAB）

```bash
# 构建 Android App Bundle（Google Play 推荐）
flutter build appbundle --release --no-tree-shake-icons

# 输出文件：
# - app-release.aab

# 构建带混淆的 AAB
flutter build appbundle --release \
    --obfuscate \
    --split-debug-info=build/app/outputs/symbols \
    --no-tree-shake-icons
```

### 命令详解

| 参数                      | 说明                   |
|-------------------------|----------------------|
| `--release`             | 发布模式，启用优化            |
| `--split-per-abi`       | 为每个 ABI 生成独立 APK     |
| `--target-platform`     | 指定目标架构               |
| `--obfuscate`           | 启用代码混淆               |
| `--split-debug-info`    | 分离调试符号               |
| `--no-tree-shake-icons` | 禁用图标树摇（media_kit 需要） |
| `--no-shrink`           | 禁用资源压缩（快速测试）         |

---

## 🍎 iOS 打包（仅 macOS）

### 无签名版本（测试/CI）

```bash
# 构建无签名 IPA（用于自动化测试）
flutter build ios --release --no-codesign

# 手动打包为 IPA
cd build/ios/iphoneos
mkdir Payload
cp -r Runner.app Payload/
zip -r Runner.ipa Payload/
rm -rf Payload
```

### 签名发布版本

```bash
# 构建签名版本（需配置证书）
flutter build ios --release

# 导出 IPA（使用 ExportOptions.plist）
xcodebuild -exportArchive \
    -archivePath build/ios/archive/Runner.xcarchive \
    -exportPath build/ios/ipa \
    -exportOptionsPlist ios/ExportOptions.plist
```

---

## 🖥️ macOS 打包（仅 macOS）

### 单架构构建

```bash
# ARM64（Apple Silicon）
flutter build macos --release --dart-define=FLUTTER_TARGET_PLATFORM=darwin-arm64

# x86_64（Intel）
flutter build macos --release --dart-define=FLUTTER_TARGET_PLATFORM=darwin-x64
```

### 打包 DMG

```bash
# 构建应用
flutter build macos --release

# 创建 DMG（使用 create-dmg 工具）
create-dmg \
  --volname "Selene" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "Selene.dmg" \
  "build/macos/Build/Products/Release/selene.app"
```

### 签名与公证（发布）

```bash
# 签名应用
codesign --force --deep --sign "Developer ID Application: <团队名称>" \
    build/macos/Build/Products/Release/selene.app

# 公证
xcrun altool --notarize-app \
    --primary-bundle-id "org.moontechlab.selene" \
    --username "<Apple ID>" \
    --password "<App 专用密码>" \
    --file Selene.dmg
```

---

## 🪟 Windows 打包（仅 Windows）

### 标准构建

```bash
# 构建 Windows 应用
flutter build windows --release

# 输出目录：
# build/windows/x64/runner/Release/
```

### 打包 ZIP

```powershell
# PowerShell
Compress-Archive \
-Path "build/windows/x64/runner/Release/*" \
-DestinationPath "selene-windows.zip"
```

### 创建安装程序（Inno Setup）

```bash
# 使用 Inno Setup 创建安装程序
iscc installer.iss
```

---

## 🐧 Linux 打包（仅 Linux）

### 标准构建

```bash
# 构建 Linux 应用
flutter build linux --release

# 输出目录：
# build/linux/x64/release/bundle/
```

### 打包 tar.gz

```bash
# 创建压缩包
cd build/linux/x64/release
tar -czf selene-linux.tar.gz bundle/
```

### 创建 deb 包（Debian/Ubuntu）

```bash
# 使用 flutter_to_debian 或直接打包
mkdir -p debian/DEBIAN
mkdir -p debian/usr/bin
mkdir -p debian/usr/share/applications
mkdir -p debian/usr/share/icons/hicolor/256x256/apps

# 复制文件
cp -r build/linux/x64/release/bundle/* debian/usr/bin/
cp logo.png debian/usr/share/icons/hicolor/256x256/apps/selene.png

# 创建控制文件
cat > debian/DEBIAN/control << EOF
Package: selene
Version: 1.6.6
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Your Name <email@example.com>
Description: Selene Video Player
 A cross-platform video player based on Flutter.
EOF

# 构建 deb 包
dpkg-deb --build debian selene_1.6.6_amd64.deb
```

---

## 🌐 Web 打包

### CanvasKit 渲染器（推荐，性能更好）

```bash
# 构建 Web 版（CanvasKit）
flutter build web --release --web-renderer canvaskit

# 输出目录：build/web/
```

### HTML 渲染器（更小体积）

```bash
# 构建 Web 版（HTML）
flutter build web --release --web-renderer html

# 或使用自动选择
flutter build web --release
```

### 部署到服务器

```bash
# 构建后部署到 Nginx
cp -r build/web/* /var/www/html/selene/

# 或使用 Firebase Hosting
firebase deploy
```

---

## 🧹 清理构建

```bash
# 清理 Flutter 构建缓存
flutter clean

# 清理 Gradle 缓存（Android）
cd android
./gradlew clean
cd ..

# 清理 iOS 构建（macOS）
cd ios
xcodebuild clean
cd ..

# 完全重置（包括依赖）
flutter clean
rm -rf pubspec.lock
rm -rf .dart_tool/
rm -rf build/
flutter pub get
```

---

## 📊 构建分析

```bash
# 分析 APK 大小
flutter build apk --analyze-size --target-platform android-arm64

# 分析 App Bundle 大小
flutter build appbundle --analyze-size

# 查看详细构建日志
flutter build apk --verbose
```

---

## ⚙️ 平台特定说明

### Android 优化配置

`android/app/build.gradle.kts` 已配置：

```kotlin
// ABI 拆分配置
splits {
    abi {
        isEnable = true
        reset()
        include("arm64-v8a", "armeabi-v7a", "x86_64")
        isUniversalApk = false
    }
}

// 发布构建启用 R8
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```

### Gradle 优化配置

`android/gradle.properties` 已启用：

```properties
org.gradle.jvmargs=-Xmx6G -XX:MaxMetaspaceSize=2G
org.gradle.daemon=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.workers.max=16
org.gradle.configureondemand=true
```

---

## ❓ 常见问题

### Q: 构建失败 "Conflicting configuration : 'x86_64,arm64-v8a'"

**A**: 已修复，确保使用 `splits.abi` 配置而非 `ndk.abiFilters`。

### Q: 构建时提示 Java 版本警告

**A**: 已统一使用 Java 17，确保 `JAVA_HOME` 指向 JDK 17：

```bash
# Windows
set JAVA_HOME=E:\ambient\jdk-17

# macOS/Linux
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
```

### Q: media_kit 相关构建错误

**A**: 确保使用 `--no-tree-shake-icons` 参数：

```bash
flutter build apk --release --no-tree-shake-icons
```

### Q: Gradle Daemon 问题

**A**: 停止并重启 Daemon：

```bash
cd android
./gradlew --stop
./gradlew clean
cd ..
flutter clean
flutter pub get
```

### Q: iOS 构建提示 "no-codesign"

**A**: 这是正常行为，无签名版本用于测试。如需签名：

1. 在 Xcode 中打开 `ios/Runner.xcworkspace`
2. 配置 Signing & Capabilities
3. 或使用 `--no-codesign` 构建后手动签名

### Q: macOS ARM64/x86_64 如何构建通用应用

**A**: 分别构建后使用 `lipo` 合并：

```bash
# 构建两个架构
./build.sh --macos-arm64-only
./build.sh --macos-x86_64-only

# 使用 lipo 创建通用二进制（可选）
lipo -create \
    build-arm64/macos/Build/Products/Release/selene.app/Contents/MacOS/selene \
    build-x86_64/macos/Build/Products/Release/selene.app/Contents/MacOS/selene \
    -output selene-universal
```

---

## 📚 参考链接

- [Flutter 官方文档](https://docs.flutter.dev/)
- [Flutter 构建发布](https://docs.flutter.dev/deployment/android)
- [media_kit 文档](https://github.com/media-kit/media-kit)
- [Dart 国际化](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization)

---

> **提示**: 本项目使用 media_kit 视频库，构建时需加上 `--no-tree-shake-icons` 参数以避免图标资源被误删。
