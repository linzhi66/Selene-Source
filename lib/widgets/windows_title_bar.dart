import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class WindowsTitleBar extends StatefulWidget {
  final bool forceBlack;
  
  const WindowsTitleBar({
    super.key,
    this.forceBlack = false,
  });

  @override
  State<WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<WindowsTitleBar> {
  bool _isAnyButtonHovered = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        final backgroundColor = widget.forceBlack
            ? Colors.transparent
            : (isDark 
                ? const Color(0xFF1e1e1e).withOpacity(0.9)
                : Colors.white.withOpacity(0.8));
        
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: backgroundColor,
          ),
          child: Row(
            children: [
              // 左侧三大金刚键（macOS 风格）
              const SizedBox(width: 12),
              _buildMacOSButton(
                onPressed: () {
                  appWindow.close();
                },
                color: const Color(0xFFFF5F57),
                hoverColor: const Color(0xFFFF3B30),
                icon: Icons.close,
                iconSize: 8,
              ),
              const SizedBox(width: 8),
              _buildMacOSButton(
                onPressed: () {
                  appWindow.minimize();
                },
                color: const Color(0xFFFEBC2E),
                hoverColor: const Color(0xFFFFB300),
                icon: Icons.remove,
                iconSize: 8,
              ),
              const SizedBox(width: 8),
              _buildMacOSButton(
                onPressed: () {
                  appWindow.maximizeOrRestore();
                },
                color: const Color(0xFF28C840),
                hoverColor: const Color(0xFF00C957),
                icon: Icons.fullscreen,
                iconSize: 8,
              ),
              // 可拖动区域
              Expanded(
                child: MoveWindow(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMacOSButton({
    required VoidCallback onPressed,
    required Color color,
    required Color hoverColor,
    required IconData icon,
    required double iconSize,
  }) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isAnyButtonHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isAnyButtonHovered = false;
        });
      },
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 1,
                offset: const Offset(0, 0.5),
              ),
            ],
          ),
          child: _isAnyButtonHovered
              ? Icon(
                  icon,
                  size: iconSize,
                  color: Colors.black.withOpacity(0.7),
                )
              : null,
        ),
      ),
    );
  }
}
