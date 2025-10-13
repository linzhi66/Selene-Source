#!/bin/bash

# Selene 构建脚本
# 用于构建安卓和 iOS 无签名版本，并将构建产物复制到根目录下

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 版本信息
APP_VERSION=""

# 读取版本号
read_version() {
    log_info "读取项目版本号..."
    
    # 从 pubspec.yaml 中提取版本号
    if [ -f "pubspec.yaml" ]; then
        APP_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: *//' | tr -d ' ')
        if [ -z "$APP_VERSION" ]; then
            log_error "无法从 pubspec.yaml 中读取版本号"
            exit 1
        fi
        log_success "项目版本号: $APP_VERSION"
    else
        log_error "pubspec.yaml 文件不存在"
        exit 1
    fi
}

# 日志函数
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

# 检查 Flutter 环境
check_flutter() {
    log_info "检查 Flutter 环境..."
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter 未安装或未添加到 PATH"
        exit 1
    fi
    
    flutter --version
    log_success "Flutter 环境检查通过"
}

# 清理之前的构建
clean_build() {
    log_info "清理之前的构建..."
    flutter clean
    
    # 清理自定义构建目录
    rm -rf ios-build
    rm -rf dist
    
    log_success "构建清理完成"
}

# 获取依赖
get_dependencies() {
    log_info "获取项目依赖..."
    flutter pub get
    log_success "依赖获取完成"
}

# 构建安卓版本
build_android() {
    log_info "开始构建安卓 armv8 和 armv7a 版本..."
    
    # 确保安卓构建目录存在
    mkdir -p build/android
    
    # 构建 APK
    flutter build apk --release --target-platform android-arm64 --split-per-abi
    flutter build apk --release --target-platform android-arm --split-per-abi
    
    log_success "安卓构建完成"
}

# 构建 iOS 无签名版本
build_ios() {
    log_info "开始构建 iOS 无签名版本..."
    
    # 检查是否在 macOS 上
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_warning "iOS 构建只能在 macOS 上进行，跳过 iOS 构建"
        return
    fi
    
    # 确保 iOS 构建目录存在
    mkdir -p build/ios
    
    # 构建 iOS 无签名版本
    flutter build ios --release --no-codesign
    
    # 检查构建是否成功
    if [ ! -d "build/ios/iphoneos/Runner.app" ]; then
        log_error "iOS 应用构建失败"
        return 1
    fi
    
    # 创建 .ipa 文件
    log_info "创建 iOS .ipa 文件..."
    
    # 确保 ios-build 目录存在
    mkdir -p ios-build
    
    cd build/ios/iphoneos
    
    # 创建 Payload 目录
    mkdir -p Payload
    cp -r Runner.app Payload/
    
    # 创建 .ipa 文件
    zip -r "../../../ios-build/Runner.ipa" Payload/
    
    # 清理临时文件
    rm -rf Payload
    
    cd ../../..
    
    log_success "iOS 构建完成"
}

# 复制构建产物到根目录
copy_artifacts() {
    log_info "复制构建产物到根目录..."
    
    # 创建输出目录
    mkdir -p dist
    
    # 复制安卓 APK
    if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
        cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "dist/selene-${APP_VERSION}-armv8.apk"
        log_success "安卓 arm64 APK 已复制到 dist/selene-${APP_VERSION}-armv8.apk"
    else
        log_warning "安卓 arm64 APK 文件未找到"
    fi
    if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
        cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "dist/selene-${APP_VERSION}-armv7a.apk"
        log_success "安卓 armv7a APK 已复制到 dist/selene-${APP_VERSION}-armv7a.apk"
    else
        log_warning "安卓 armv7a APK 文件未找到"
    fi
    
    # 复制 iOS 构建产物
    if [ -f "ios-build/Runner.ipa" ]; then
        cp ios-build/Runner.ipa "dist/selene-${APP_VERSION}.ipa"
        log_success "iOS .ipa 文件已复制到 dist/selene-${APP_VERSION}.ipa"
    else
        log_warning "iOS .ipa 文件未找到"
    fi
    
    log_success "构建产物复制完成"
}

# 显示构建结果
show_results() {
    log_info "构建结果:"
    echo ""
    
    if [ -d "dist" ]; then
        echo "📁 构建产物目录:"
        ls -la dist/
        echo ""
        
        echo "📊 文件大小:"
        du -h dist/*
        echo ""
        
        log_success "所有构建产物已保存到 dist/ 目录"
    else
        log_warning "未找到构建产物"
    fi
}

# 主函数
main() {
    echo "🚀 Selene 构建脚本启动"
    echo "=================================="
    
    # 检查参数
    BUILD_ANDROID=true
    BUILD_IOS=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --android-only)
                BUILD_IOS=false
                shift
                ;;
            --ios-only)
                BUILD_ANDROID=false
                shift
                ;;
            --help)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --android-only    只构建安卓版本"
                echo "  --ios-only       只构建 iOS 版本"
                echo "  --help           显示此帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
    
    # 执行构建流程
    read_version
    check_flutter
    clean_build
    get_dependencies
    
    if [ "$BUILD_ANDROID" = true ]; then
        build_android
    fi
    
    if [ "$BUILD_IOS" = true ]; then
        build_ios
    fi
    
    copy_artifacts
    show_results
    
    echo "=================================="
    log_success "构建完成！"
}

# 运行主函数
main "$@"
