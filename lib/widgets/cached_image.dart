import 'package:flutter/material.dart';

/// 优化的图片加载组件
///
/// 提供缓存、错误处理和加载占位符
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? cacheWidth;
  final int? cacheHeight;
  final BorderRadius? borderRadius;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.cacheWidth,
    this.cacheHeight,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: FilterQuality.low,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(
                Icons.broken_image,
                color: Colors.grey,
              ),
            );
      },
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}

/// 用于网络台标/Logo 的优化图片组件
class LogoImage extends StatelessWidget {
  final String logoUrl;
  final double? size;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const LogoImage({
    super.key,
    required this.logoUrl,
    this.size,
    this.width,
    this.height,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Colors.grey[200];
    final br = borderRadius ?? BorderRadius.circular(4);

    return Container(
      width: width ?? size,
      height: height ?? size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: br,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: OptimizedImage(
          imageUrl: logoUrl,
          width: width ?? size,
          height: height ?? size,
          fit: BoxFit.contain,
          cacheWidth: (width ?? size ?? 100).toInt() * 2,
          cacheHeight: (height ?? size ?? 100).toInt() * 2,
          placeholder: Container(
            color: bgColor,
            child: const Icon(
              Icons.tv,
              color: Colors.grey,
            ),
          ),
          errorWidget: Container(
            color: bgColor,
            child: const Icon(
              Icons.tv,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
