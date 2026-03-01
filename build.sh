#!/bin/bash

# Selene 构建脚本
# 用于构建跨平台版本，支持 Android、iOS、macOS、Windows、Linux、Web

set -euo pipefail  # 严格模式：遇到错误、未定义变量、管道失败时退出

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 版本信息
APP_VERSION=""
# SCRIPT_DIR 保留供外部调用参考
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_TIME=$(date +%s)

# ============================================
# 日志函数
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示耗时
show_duration() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    log_info "总耗时: ${minutes}分${seconds}秒"
}

# 错误处理
error_exit() {
    log_error "$1"
    show_duration
    exit 1
}

# ============================================
# 前置检查
# ============================================

# 读取版本号
read_version() {
    log_info "读取项目版本号..."
    
    if [ ! -f "pubspec.yaml" ]; then
        error_exit "pubspec.yaml 文件不存在"
    fi
    
    # 从 pubspec.yaml 中提取版本号
    APP_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: *//' | tr -d ' ' | cut -d'+' -f1)
    
    if [ -z "$APP_VERSION" ]; then
        error_exit "无法从 pubspec.yaml 中读取版本号"
    fi
    
    log_success "项目版本号: $APP_VERSION"
}

# 检查 Flutter 环境
check_flutter() {
    log_info "检查 Flutter 环境..."
    
    if ! command -v flutter &> /dev/null; then
        error_exit "Flutter 未安装或未添加到 PATH"
    fi
    
    # 检查 Flutter 版本
    local flutter_version
    flutter_version=""
    flutter_version=$(flutter --version | head -1)
    log_info "$flutter_version"
    
    # 检查是否有设备连接
    log_info "可用设备:"
    flutter devices
    
    log_success "Flutter 环境检查通过"
}

# 检查是否运行在 macOS（用于 iOS/macOS 构建）
is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

# 检查是否运行在 Windows（通过 MSYS/Cygwin/Git Bash）
is_windows() {
    [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "${MSYSTEM:-}" ]]
}

# 检查是否运行在 Linux
is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

# ============================================
# 清理与准备
# ============================================

# 清理之前的构建（选择性清理，保留 Gradle 缓存）
clean_build() {
    log_info "清理之前的构建..."
    
    # 清理 Flutter 构建缓存
    flutter clean || log_warning "flutter clean 失败，继续执行"
    
    # 清理自定义构建目录
    rm -rf ios-build dist build-arm64 build-x86_64 build-windows build-linux
    
    log_success "构建清理完成"
}

# 获取依赖
get_dependencies() {
    log_info "获取项目依赖..."
    flutter pub get || error_exit "依赖获取失败"
    log_success "依赖获取完成"
}

# 安装 iOS/macOS 依赖（仅 macOS）
install_pods() {
    if is_macos; then
        log_info "检查 CocoaPods 依赖..."
        if [ -d "ios" ] && [ -f "ios/Podfile" ]; then
            (cd ios && pod install --repo-update) || log_warning "iOS pod install 失败"
        fi
        if [ -d "macos" ] && [ -f "macos/Podfile" ]; then
            (cd macos && pod install --repo-update) || log_warning "macOS pod install 失败"
        fi
    fi
}

# ============================================
# 各平台构建函数
# ============================================

# 构建 Android 版本
build_android() {
    log_info "========================================"
    log_info "开始构建 Android 版本..."
    log_info "========================================"
    
    # 确保目录存在
    mkdir -p build/android
    
    # 构建 APK - 使用优化的 Gradle 配置
    # 注意：media_kit 需要 --no-tree-shake-icons
    flutter build apk --release \
        --target-platform android-arm64,android-arm \
        --split-per-abi \
        --no-tree-shake-icons \
        --obfuscate \
        --split-debug-info=build/app/outputs/symbols \
        || error_exit "Android APK 构建失败"
    
    log_success "Android APK 构建完成"
    
    # 同时构建 AAB（Google Play 上架用）
    log_info "构建 Android App Bundle (AAB)..."
    flutter build appbundle --release \
        --no-tree-shake-icons \
        --obfuscate \
        --split-debug-info=build/app/outputs/symbols \
        || log_warning "AAB 构建失败（非致命错误）"
    
    if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
        log_success "Android AAB 构建完成"
    fi
}

# 构建 iOS 无签名版本（仅 macOS）
build_ios() {
    log_info "========================================"
    log_info "开始构建 iOS 版本..."
    log_info "========================================"
    
    if ! is_macos; then
        log_warning "iOS 构建只能在 macOS 上进行，跳过"
        return 0
    fi
    
    # 确保 iOS 依赖已安装
    if [ -f "ios/Podfile" ]; then
        log_info "安装 iOS CocoaPods 依赖..."
        (cd ios && pod install) || error_exit "iOS pod install 失败"
    fi
    
    # 构建 iOS 无签名版本
    flutter build ios --release --no-codesign \
        || error_exit "iOS 构建失败"
    
    # 检查构建是否成功
    if [ ! -d "build/ios/iphoneos/Runner.app" ]; then
        error_exit "iOS 应用构建失败：Runner.app 不存在"
    fi
    
    # 创建 .ipa 文件
    log_info "创建 iOS .ipa 文件..."
    mkdir -p ios-build
    
    (
        cd build/ios/iphoneos
        rm -rf Payload
        mkdir -p Payload
        cp -r Runner.app Payload/
        zip -r "../../../ios-build/Runner.ipa" Payload/ -q
        rm -rf Payload
    )
    
    if [ ! -f "ios-build/Runner.ipa" ]; then
        error_exit "iOS IPA 打包失败"
    fi
    
    log_success "iOS 构建完成: ios-build/Runner.ipa"
}

# 构建 macOS ARM64 版本（仅 macOS）
build_macos_arm64() {
    log_info "========================================"
    log_info "开始构建 macOS ARM64 版本..."
    log_info "========================================"
    
    if ! is_macos; then
        log_warning "macOS 构建只能在 macOS 上进行，跳过"
        return 0
    fi
    
    # 创建独立的构建目录
    mkdir -p build-arm64
    
    # 使用 rsync 或 cp 复制文件
    if command -v rsync &> /dev/null; then
        rsync -a --exclude='build*' --exclude='.dart_tool' --exclude='build-arm64' --exclude='build-x86_64' . build-arm64/
    else
        # 兼容没有 rsync 的系统
        cp -r . build-arm64/
        rm -rf build-arm64/build* build-arm64/.dart_tool build-arm64/build-arm64 build-arm64/build-x86_64
    fi
    
    (
        cd build-arm64
        
        # 安装依赖
        flutter pub get || { log_error "ARM64 依赖获取失败"; exit 1; }
        
        if [ -f "macos/Podfile" ]; then
            (cd macos && pod install) || { log_error "ARM64 pod install 失败"; exit 1; }
        fi
        
        # 构建 ARM64 版本
        flutter build macos --release \
            --dart-define=FLUTTER_TARGET_PLATFORM=darwin-arm64 \
            || { log_error "macOS ARM64 构建失败"; exit 1; }
        
        # 备份构建产物
        if [ -d "build/macos/Build/Products/Release/selene.app" ]; then
            mkdir -p ../build/macos-arm64
            cp -R build/macos/Build/Products/Release/selene.app ../build/macos-arm64/
            log_success "macOS ARM64 构建完成"
        else
            log_error "macOS ARM64 构建产物不存在"
            exit 1
        fi
    ) || error_exit "macOS ARM64 构建失败"
}

# 构建 macOS x86_64 版本（仅 macOS）
build_macos_x86_64() {
    log_info "========================================"
    log_info "开始构建 macOS x86_64 版本..."
    log_info "========================================"
    
    if ! is_macos; then
        log_warning "macOS 构建只能在 macOS 上进行，跳过"
        return 0
    fi
    
    # 创建独立的构建目录
    mkdir -p build-x86_64
    
    if command -v rsync &> /dev/null; then
        rsync -a --exclude='build*' --exclude='.dart_tool' --exclude='build-arm64' --exclude='build-x86_64' . build-x86_64/
    else
        cp -r . build-x86_64/
        rm -rf build-x86_64/build* build-x86_64/.dart_tool build-x86_64/build-arm64 build-x86_64/build-x86_64
    fi
    
    (
        cd build-x86_64
        
        flutter pub get || { log_error "x86_64 依赖获取失败"; exit 1; }
        
        if [ -f "macos/Podfile" ]; then
            (cd macos && pod install) || { log_error "x86_64 pod install 失败"; exit 1; }
        fi
        
        flutter build macos --release \
            --dart-define=FLUTTER_TARGET_PLATFORM=darwin-x64 \
            || { log_error "macOS x86_64 构建失败"; exit 1; }
        
        if [ -d "build/macos/Build/Products/Release/selene.app" ]; then
            mkdir -p ../build/macos-x86_64
            cp -R build/macos/Build/Products/Release/selene.app ../build/macos-x86_64/
            log_success "macOS x86_64 构建完成"
        else
            log_error "macOS x86_64 构建产物不存在"
            exit 1
        fi
    ) || error_exit "macOS x86_64 构建失败"
}

# 构建 macOS 通用版本（仅 macOS，顺序构建）
build_macos() {
    log_info "开始构建 macOS 双架构版本..."
    build_macos_arm64
    build_macos_x86_64
    log_success "macOS 所有架构构建完成"
}

# 构建 Windows 版本（仅 Windows）
build_windows() {
    log_info "========================================"
    log_info "开始构建 Windows 版本..."
    log_info "========================================"
    
    if ! is_windows && ! command -v MSBuild.exe &> /dev/null; then
        log_warning "Windows 构建需要 Windows 环境和 Visual Studio，跳过"
        return 0
    fi
    
    # Windows 构建优化环境变量
    export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc 2>/dev/null || echo 4)}"
    
    # 构建参数
    local build_args=(
        "--release"
        "--no-tree-shake-icons"
    )
    
    flutter build windows "${build_args[@]}" \
        || error_exit "Windows 构建失败"
    
    if [ -d "build/windows/x64/runner/Release" ]; then
        mkdir -p build-windows
        cp -r build/windows/x64/runner/Release/* build-windows/
        
        # 显示构建产物大小
        local exe_size
        exe_size=$(du -h build-windows/selene.exe 2>/dev/null | cut -f1)
        log_success "Windows 构建完成 (selene.exe: ${exe_size})"
    fi
}

# 构建 Linux 版本（仅 Linux）
build_linux() {
    log_info "========================================"
    log_info "开始构建 Linux 版本..."
    log_info "========================================"
    
    if ! is_linux; then
        log_warning "Linux 构建只能在 Linux 上进行，跳过"
        return 0
    fi
    
    flutter build linux --release \
        || error_exit "Linux 构建失败"
    
    if [ -d "build/linux/x64/release/bundle" ]; then
        mkdir -p build-linux
        cp -r build/linux/x64/release/bundle/* build-linux/
        log_success "Linux 构建完成"
    fi
}

# 构建 Web 版本
build_web() {
    log_info "========================================"
    log_info "开始构建 Web 版本..."
    log_info "========================================"
    
    flutter build web --release --web-renderer canvaskit \
        || error_exit "Web 构建失败"
    
    log_success "Web 构建完成: build/web/"
}

# ============================================
# 打包与输出
# ============================================

# 复制构建产物到 dist 目录
copy_artifacts() {
    log_info "========================================"
    log_info "复制构建产物到 dist 目录..."
    log_info "========================================"
    
    mkdir -p dist
    local copied_count=0
    
    # Android APK
    if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
        cp "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "dist/selene-${APP_VERSION}-android-arm64.apk"
        log_success "Android arm64 APK 已复制"
        ((copied_count++))
    fi
    
    if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
        cp "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" "dist/selene-${APP_VERSION}-android-armv7a.apk"
        log_success "Android armv7a APK 已复制"
        ((copied_count++))
    fi
    
    # Android AAB
    if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
        cp "build/app/outputs/bundle/release/app-release.aab" "dist/selene-${APP_VERSION}-android.aab"
        log_success "Android AAB 已复制"
        ((copied_count++))
    fi
    
    # iOS IPA
    if [ -f "ios-build/Runner.ipa" ]; then
        cp "ios-build/Runner.ipa" "dist/selene-${APP_VERSION}-ios.ipa"
        log_success "iOS IPA 已复制"
        ((copied_count++))
    fi
    
    # macOS DMG（ARM64）
    if [ -d "build/macos-arm64/selene.app" ]; then
        log_info "打包 macOS ARM64 DMG..."
        local dmg_name="selene-${APP_VERSION}-macos-arm64.dmg"
        
        if command -v hdiutil &> /dev/null; then
            local tmp_dir
    tmp_dir=$(mktemp -d)
            cp -R "build/macos-arm64/selene.app" "$tmp_dir/"
            hdiutil create -volname "Selene" \
                -srcfolder "$tmp_dir" \
                -ov -format UDZO \
                "dist/${dmg_name}" -quiet
            rm -rf "$tmp_dir"
            log_success "macOS ARM64 DMG 已创建"
            ((copied_count++))
        else
            # 没有 hdiutil 时直接复制 app
            cp -R "build/macos-arm64/selene.app" "dist/selene-${APP_VERSION}-macos-arm64.app"
            log_success "macOS ARM64 app 已复制"
            ((copied_count++))
        fi
    fi
    
    # macOS DMG（x86_64）
    if [ -d "build/macos-x86_64/selene.app" ]; then
        log_info "打包 macOS x86_64 DMG..."
        local dmg_name="selene-${APP_VERSION}-macos-x86_64.dmg"
        
        if command -v hdiutil &> /dev/null; then
            local tmp_dir
            tmp_dir=$(mktemp -d)
            cp -R "build/macos-x86_64/selene.app" "$tmp_dir/"
            hdiutil create -volname "Selene" \
                -srcfolder "$tmp_dir" \
                -ov -format UDZO \
                "dist/${dmg_name}" -quiet
            rm -rf "$tmp_dir"
            log_success "macOS x86_64 DMG 已创建"
            ((copied_count++))
        else
            cp -R "build/macos-x86_64/selene.app" "dist/selene-${APP_VERSION}-macos-x86_64.app"
            log_success "macOS x86_64 app 已复制"
            ((copied_count++))
        fi
    fi
    
    # Windows
    if [ -d "build-windows" ]; then
        if command -v zip &> /dev/null; then
            (cd build-windows && zip -r "../dist/selene-${APP_VERSION}-windows.zip" . -q)
            log_success "Windows ZIP 已创建"
        else
            cp -r build-windows "dist/selene-${APP_VERSION}-windows"
            log_success "Windows 文件已复制"
        fi
        ((copied_count++))
    fi
    
    # Linux
    if [ -d "build-linux" ]; then
        local tar_name="selene-${APP_VERSION}-linux.tar.gz"
        tar -czf "dist/${tar_name}" -C build-linux .
        log_success "Linux tar.gz 已创建"
        ((copied_count++))
    fi
    
    # Web
    if [ -d "build/web" ]; then
        local web_name="selene-${APP_VERSION}-web"
        cp -r build/web "dist/${web_name}"
        (cd dist && tar -czf "${web_name}.tar.gz" "${web_name}" && rm -rf "${web_name}")
        log_success "Web 已打包"
        ((copied_count++))
    fi
    
    if [ $copied_count -eq 0 ]; then
        log_warning "未找到任何构建产物"
    else
        log_success "共复制/创建 $copied_count 个构建产物"
    fi
}

# 显示构建结果
show_results() {
    log_info "========================================"
    log_info "构建结果汇总"
    log_info "========================================"
    
    if [ -d "dist" ] && [ "$(ls -A dist 2>/dev/null)" ]; then
        echo ""
        echo "📁 构建产物列表 (dist/):"
        ls -lh dist/ 2>/dev/null || ls -l dist/
        echo ""
        
        # 显示各文件大小
        echo "📊 文件大小明细:"
        du -h dist/* 2>/dev/null || du -sh dist/*
        echo ""
        
        log_success "所有构建产物已保存到 dist/ 目录"
    else
        log_warning "dist/ 目录为空或未找到"
    fi
    
    # 显示构建产物位置
    echo ""
    log_info "构建产物位置:"
    [ -d "build/app/outputs/flutter-apk" ] && echo "  - Android APK: build/app/outputs/flutter-apk/"
    [ -d "build/app/outputs/bundle" ] && echo "  - Android AAB: build/app/outputs/bundle/release/"
    [ -f "ios-build/Runner.ipa" ] && echo "  - iOS IPA: ios-build/Runner.ipa"
    [ -d "build/macos-arm64" ] && echo "  - macOS ARM64: build/macos-arm64/"
    [ -d "build/macos-x86_64" ] && echo "  - macOS x86_64: build/macos-x86_64/"
    [ -d "build-windows" ] && echo "  - Windows: build-windows/"
    [ -d "build-linux" ] && echo "  - Linux: build-linux/"
    [ -d "build/web" ] && echo "  - Web: build/web/"
    
    show_duration
}

# ============================================
# 清理临时文件
# ============================================

cleanup() {
    log_info "========================================"
    log_info "清理临时构建目录..."
    log_info "========================================"
    
    # 只清理中间构建目录，保留主 build 目录（包含符号文件）
    rm -rf build-arm64 build-x86_64 build-windows build-linux ios-build
    
    # 可选：清理 build 目录中的临时文件，保留符号文件
    # rm -rf build/{ios,macos,windows,linux,web} 2>/dev/null || true
    
    log_success "临时目录已清理"
}

# ============================================
# 帮助信息
# ============================================

show_help() {
    cat << EOF
Selene 构建脚本

用法: $0 [选项]

选项:
  平台选择:
    --android-only        只构建 Android 版本
    --ios-only            只构建 iOS 版本（仅 macOS）
    --macos-arm64-only    只构建 macOS ARM64 版本（仅 macOS）
    --macos-x86_64-only   只构建 macOS x86_64 版本（仅 macOS）
    --macos-only          构建 macOS 所有架构（仅 macOS）
    --apple-only          构建所有 Apple 平台（iOS + macOS，仅 macOS）
    --windows-only        只构建 Windows 版本（仅 Windows）
    --linux-only          只构建 Linux 版本（仅 Linux）
    --web-only            只构建 Web 版本
    
  构建模式:
    --sequential          顺序构建（默认并行）
    --no-clean            跳过 clean 步骤（保留缓存，快速构建）
    
  其他:
    --help, -h            显示此帮助信息

示例:
  $0                    # 构建所有平台
  $0 --android-only     # 仅构建 Android
  $0 --apple-only       # 构建 iOS + macOS
  $0 --no-clean         # 不清理缓存，快速重新构建

环境要求:
  - Flutter SDK >= 3.4.3
  - Android SDK（构建 Android）
  - Xcode（构建 iOS/macOS，仅 macOS）
  - Visual Studio（构建 Windows，仅 Windows）
  - GTK 开发库（构建 Linux，仅 Linux）

EOF
}

# ============================================
# 主函数
# ============================================

main() {
    # 默认构建配置
    BUILD_ANDROID=false
    BUILD_IOS=false
    BUILD_MACOS_ARM64=false
    BUILD_MACOS_X86_64=false
    BUILD_WINDOWS=false
    BUILD_LINUX=false
    BUILD_WEB=false
    PARALLEL_BUILD=true
    DO_CLEAN=true
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --android-only)
                BUILD_ANDROID=true
                shift
                ;;
            --ios-only)
                BUILD_IOS=true
                shift
                ;;
            --macos-arm64-only)
                BUILD_MACOS_ARM64=true
                shift
                ;;
            --macos-x86_64-only)
                BUILD_MACOS_X86_64=true
                shift
                ;;
            --macos-only)
                BUILD_MACOS_ARM64=true
                BUILD_MACOS_X86_64=true
                shift
                ;;
            --apple-only)
                BUILD_IOS=true
                BUILD_MACOS_ARM64=true
                BUILD_MACOS_X86_64=true
                shift
                ;;
            --windows-only)
                BUILD_WINDOWS=true
                shift
                ;;
            --linux-only)
                BUILD_LINUX=true
                shift
                ;;
            --web-only)
                BUILD_WEB=true
                shift
                ;;
            --sequential)
                PARALLEL_BUILD=false
                shift
                ;;
            --no-clean)
                DO_CLEAN=false
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 如果没有指定平台，默认构建所有可用平台
    if [[ "$BUILD_ANDROID" == "false" && \
          "$BUILD_IOS" == "false" && \
          "$BUILD_MACOS_ARM64" == "false" && \
          "$BUILD_MACOS_X86_64" == "false" && \
          "$BUILD_WINDOWS" == "false" && \
          "$BUILD_LINUX" == "false" && \
          "$BUILD_WEB" == "false" ]]; then
        BUILD_ANDROID=true
        BUILD_IOS=true
        BUILD_MACOS_ARM64=true
        BUILD_MACOS_X86_64=true
        BUILD_WINDOWS=true
        BUILD_LINUX=true
        # Web 默认不构建，需要显式指定
    fi
    
    # 显示构建计划
    echo "🚀 Selene 构建脚本启动"
    echo "=================================="
    log_info "版本: $APP_VERSION"
    log_info "并行构建: $PARALLEL_BUILD"
    log_info "清理缓存: $DO_CLEAN"
    echo ""
    log_info "构建计划:"
    $BUILD_ANDROID && echo "  ✓ Android"
    $BUILD_IOS && echo "  ✓ iOS"
    $BUILD_MACOS_ARM64 && echo "  ✓ macOS ARM64"
    $BUILD_MACOS_X86_64 && echo "  ✓ macOS x86_64"
    $BUILD_WINDOWS && echo "  ✓ Windows"
    $BUILD_LINUX && echo "  ✓ Linux"
    $BUILD_WEB && echo "  ✓ Web"
    echo "=================================="
    echo ""
    
    # 执行构建流程
    read_version
    check_flutter
    
    if $DO_CLEAN; then
        clean_build
    else
        log_info "跳过清理步骤（使用 --no-clean 加快构建）"
    fi
    
    get_dependencies
    install_pods
    
    # 执行构建
    if $PARALLEL_BUILD; then
        log_info "使用并行构建模式..."
        pids=()
        
        $BUILD_ANDROID && { build_android & pids+=($!); }
        $BUILD_IOS && { build_ios & pids+=($!); }
        $BUILD_MACOS_ARM64 && { build_macos_arm64 & pids+=($!); }
        $BUILD_MACOS_X86_64 && { build_macos_x86_64 & pids+=($!); }
        $BUILD_WINDOWS && { build_windows & pids+=($!); }
        $BUILD_LINUX && { build_linux & pids+=($!); }
        $BUILD_WEB && { build_web & pids+=($!); }
        
        if [ ${#pids[@]} -gt 0 ]; then
            log_info "等待 ${#pids[@]} 个并行构建任务完成..."
            local failed=0
            for pid in "${pids[@]}"; do
                if ! wait "$pid"; then
                    ((failed++))
                    log_warning "构建进程 $pid 失败"
                fi
            done
            
            if [ $failed -gt 0 ]; then
                log_warning "$failed 个构建任务失败"
            else
                log_success "所有并行构建任务已完成"
            fi
        fi
    else
        log_info "使用顺序构建模式..."
        $BUILD_ANDROID && build_android
        $BUILD_IOS && build_ios
        $BUILD_MACOS_ARM64 && build_macos_arm64
        $BUILD_MACOS_X86_64 && build_macos_x86_64
        $BUILD_WINDOWS && build_windows
        $BUILD_LINUX && build_linux
        $BUILD_WEB && build_web
    fi
    
    # 复制产物并显示结果
    copy_artifacts
    show_results
    
    # 清理临时文件
    cleanup
    
    echo "=================================="
    log_success "构建流程全部完成！"
}

# 运行主函数
main "$@"
