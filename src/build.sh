#!/bin/bash

# OneClip 构建脚本
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[SUCCESS] $1"
}

log_info "🚀 构建 OneClip..."

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

log_info "📁 项目目录: $PROJECT_DIR"
log_info "📦 输出目录: $OUTPUT_DIR"

# 清理并构建
log_info "🧹 清理之前的构建..."
xcodebuild -project "$PROJECT_DIR/OneClip.xcodeproj" -scheme OneClip -configuration Debug clean
if [ $? -ne 0 ]; then
    log_error "清理失败"
    exit 1
fi

log_info "🔨 开始构建..."
xcodebuild -project "$PROJECT_DIR/OneClip.xcodeproj" -scheme OneClip -configuration Debug build
if [ $? -ne 0 ]; then
    log_error "构建失败"
    exit 1
fi

# 查找构建产物
DERIVED_DATA_DIR=$(xcodebuild -showBuildSettings -project "$PROJECT_DIR/OneClip.xcodeproj" -scheme OneClip -configuration Debug | grep " BUILD_DIR " | sed 's/.*= //')
SOURCE_APP="$DERIVED_DATA_DIR/Debug/OneClip.app"

if [ -d "$SOURCE_APP" ]; then
    log_success "✅ 构建成功"
    log_info "📋 复制应用到输出目录..."
    
    # 删除旧的应用（如果存在）
    if [ -d "$OUTPUT_DIR/OneClip.app" ]; then
        rm -rf "$OUTPUT_DIR/OneClip.app"
    fi
    
    # 复制新的应用
    cp -R "$SOURCE_APP" "$OUTPUT_DIR/"
    
    log_success "✅ OneClip.app 已复制到: $OUTPUT_DIR/OneClip.app"
    
    # 显示应用信息
    if [ -f "$OUTPUT_DIR/OneClip.app/Contents/Info.plist" ]; then
        parse_plist_value() {
            plutil -p "$1" | grep "$2" | sed 's/.*=> "//' | sed 's/"//'
        }
        
        VERSION=$(parse_plist_value "$OUTPUT_DIR/OneClip.app/Contents/Info.plist" CFBundleShortVersionString)
        BUILD=$(parse_plist_value "$OUTPUT_DIR/OneClip.app/Contents/Info.plist" CFBundleVersion)
        log_info "📱 应用版本: $VERSION (Build $BUILD)"
    fi
    
    # 计算应用大小
    APP_SIZE=$(du -sh "$OUTPUT_DIR/OneClip.app" | cut -f1)
    log_info "💾 应用大小: $APP_SIZE"
    
    log_info "🎉 构建完成！"
    log_info "📍 应用位置: $OUTPUT_DIR/OneClip.app"
    log_info "🚀 可以直接运行: open \"$OUTPUT_DIR/OneClip.app\""
    
else
    log_error "❌ 构建失败，未找到应用文件"
    log_error "检查 Xcode 构建日志获取详细信息"
    exit 1
fi
