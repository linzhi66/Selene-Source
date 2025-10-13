import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../utils/device_utils.dart';
import 'user_menu.dart';

class MainLayout extends StatefulWidget {
  final Widget content;
  final int currentBottomNavIndex;
  final Function(int) onBottomNavChanged;
  final String selectedTopTab;
  final Function(String) onTopTabChanged;
  final bool isSearchMode;
  final Function(bool)? onSearchModeChanged;
  final VoidCallback? onHomeTap;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final String? searchQuery;
  final Function(String)? onSearchQueryChanged;
  final Function(String)? onSearchSubmitted;
  final VoidCallback? onClearSearch;

  const MainLayout({
    super.key,
    required this.content,
    required this.currentBottomNavIndex,
    required this.onBottomNavChanged,
    required this.selectedTopTab,
    required this.onTopTabChanged,
    this.isSearchMode = false,
    this.onSearchModeChanged,
    this.onHomeTap,
    this.searchController,
    this.searchFocusNode,
    this.searchQuery,
    this.onSearchQueryChanged,
    this.onSearchSubmitted,
    this.onClearSearch,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isSearchButtonPressed = false;
  bool _showUserMenu = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Theme(
          data: themeService.isDarkMode
              ? themeService.darkTheme
              : themeService.lightTheme,
          child: Scaffold(
            resizeToAvoidBottomInset: !widget.isSearchMode,
            body: Stack(
              children: [
                // 主要内容区域
                Column(
                  children: [
                    // 主内容区域（包含header和content）
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: themeService.isDarkMode
                              ? const Color(0xFF000000) // 深色模式纯黑色
                              : null,
                          gradient: themeService.isDarkMode
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFe6f3fb), // 浅色模式渐变
                                    Color(0xFFeaf3f7),
                                    Color(0xFFf7f7f3),
                                    Color(0xFFe9ecef),
                                    Color(0xFFdbe3ea),
                                    Color(0xFFd3dde6),
                                  ],
                                  stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
                                ),
                        ),
                        child: Column(
                          children: [
                            // 固定 Header
                            _buildHeader(context, themeService),
                            // 主要内容区域
                            Expanded(
                              child: widget.content,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 底部导航栏
                    _buildBottomNavBar(themeService),
                  ],
                ),
                // 用户菜单覆盖层 - 现在会覆盖整个屏幕包括navbar
                if (_showUserMenu)
                  UserMenu(
                    isDarkMode: themeService.isDarkMode,
                    onClose: () {
                      setState(() {
                        _showUserMenu = false;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ThemeService themeService) {
    final isTablet = DeviceUtils.isTablet(context);
    
    // macOS 下需要额外的顶部 padding 来避免与透明标题栏重叠
    final topPadding = DeviceUtils.isMacOS() 
        ? MediaQuery.of(context).padding.top + 32 
        : MediaQuery.of(context).padding.top + 8;

    return Container(
      padding: EdgeInsets.only(
        top: topPadding,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: widget.isSearchMode
            ? themeService.isDarkMode
                ? const Color(0xFF121212)
                : const Color(0xFFf5f5f5)
            : themeService.isDarkMode
                ? const Color(0xFF1e1e1e).withOpacity(0.9)
                : Colors.white.withOpacity(0.8),
        border: widget.isSearchMode
            ? null
            : Border(
                bottom: BorderSide(
                  color: themeService.isDarkMode
                      ? const Color(0xFF333333).withOpacity(0.3)
                      : Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
      ),
      child: widget.isSearchMode
          ? _buildSearchHeader(context, themeService, isTablet)
          : _buildNormalHeader(context, themeService),
    );
  }

  Widget _buildNormalHeader(BuildContext context, ThemeService themeService) {
    return SizedBox(
      height: 40, // 固定高度，与搜索框高度一致
      child: Stack(
        children: [
          // 左侧搜索图标
          Positioned(
            left: 0,
            top: 4,
            child: GestureDetector(
              onTap: () {
                // 防止重复点击
                if (_isSearchButtonPressed) return;

                setState(() {
                  _isSearchButtonPressed = true;
                });

                final callback = widget.onSearchModeChanged;
                if (callback != null) {
                  callback(!widget.isSearchMode);
                }

                // 延迟重置按钮状态，防止快速重复点击
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      _isSearchButtonPressed = false;
                    });
                  }
                });
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(
                    LucideIcons.search,
                    color: themeService.isDarkMode
                        ? const Color(0xFFffffff)
                        : const Color(0xFF2c3e50),
                    size: 24,
                    weight: 1.0,
                  ),
                ),
              ),
            ),
          ),
          // 完全居中的 Logo
          Center(
            child: GestureDetector(
              onTap: widget.onHomeTap,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Selene',
                style: GoogleFonts.sourceCodePro(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: themeService.isDarkMode
                      ? Colors.white
                      : const Color(0xFF2c3e50),
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          // 右侧按钮组
          Positioned(
            right: 0,
            top: 4,
            child: _buildRightButtons(themeService),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(
      BuildContext context, ThemeService themeService, bool isTablet) {
    final searchBoxWidget = Container(
      decoration: BoxDecoration(
        color: themeService.isDarkMode ? const Color(0xFF1e1e1e) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: themeService.isDarkMode
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: widget.searchController,
        focusNode: widget.searchFocusNode,
        autofocus: false,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: '搜索电影、剧集、动漫...',
          hintStyle: GoogleFonts.poppins(
            color: themeService.isDarkMode
                ? const Color(0xFF666666)
                : const Color(0xFF95a5a6),
            fontSize: 14,
          ),
          suffixIcon: isTablet
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 平板模式：使用 IconButton
                    if (widget.searchQuery?.isNotEmpty ?? false)
                      IconButton(
                        icon: Icon(
                          LucideIcons.x,
                          color: themeService.isDarkMode
                              ? const Color(0xFFb0b0b0)
                              : const Color(0xFF7f8c8d),
                          size: 18,
                        ),
                        onPressed: widget.onClearSearch,
                      ),
                    IconButton(
                      padding: const EdgeInsets.only(left: 2.0, right: 8.0),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        LucideIcons.search,
                        color: (widget.searchQuery?.trim().isNotEmpty ?? false)
                            ? const Color(0xFF27ae60)
                            : themeService.isDarkMode
                                ? const Color(0xFFb0b0b0)
                                : const Color(0xFF7f8c8d),
                        size: 18,
                      ),
                      onPressed:
                          (widget.searchQuery?.trim().isNotEmpty ?? false)
                              ? () => widget.onSearchSubmitted
                                  ?.call(widget.searchQuery!)
                              : null,
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 非平板模式：紧凑样式，无点击效果
                    if (widget.searchQuery?.isNotEmpty ?? false)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: widget.onClearSearch,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              LucideIcons.x,
                              color: themeService.isDarkMode
                                  ? const Color(0xFFb0b0b0)
                                  : const Color(0xFF7f8c8d),
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: (widget.searchQuery?.trim().isNotEmpty ?? false)
                            ? () => widget.onSearchSubmitted
                                ?.call(widget.searchQuery!)
                            : null,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 4.0, right: 12.0, top: 8.0, bottom: 8.0),
                          child: Icon(
                            LucideIcons.search,
                            color:
                                (widget.searchQuery?.trim().isNotEmpty ?? false)
                                    ? const Color(0xFF27ae60)
                                    : themeService.isDarkMode
                                        ? const Color(0xFFb0b0b0)
                                        : const Color(0xFF7f8c8d),
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          isDense: true,
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: themeService.isDarkMode
              ? const Color(0xFFffffff)
              : const Color(0xFF2c3e50),
          height: 1.2,
        ),
        onSubmitted: widget.onSearchSubmitted,
        onChanged: widget.onSearchQueryChanged,
      ),
    );

    // 平板模式下居中
    if (isTablet) {
      return SizedBox(
        height: 40, // 固定高度
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 搜索框在整个屏幕水平居中
            Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.5,
                child: searchBoxWidget,
              ),
            ),
            // 右侧按钮 - 垂直居中
            Positioned(
              right: 0,
              child: _buildRightButtons(themeService),
            ),
          ],
        ),
      );
    }

    // 非平板模式下，搜索框居左，右侧留出按钮空间
    return SizedBox(
      height: 40, // 固定高度
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: searchBoxWidget),
          const SizedBox(width: 16),
          _buildRightButtons(themeService),
        ],
      ),
    );
  }

  Widget _buildRightButtons(ThemeService themeService) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 深浅模式切换按钮
        SizedBox(
          width: 32,
          height: 32,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  themeService.toggleTheme(context);
                },
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: child,
                      );
                    },
                    child: Icon(
                      themeService.isDarkMode
                          ? LucideIcons.sun
                          : LucideIcons.moon,
                      key: ValueKey(themeService.isDarkMode),
                      color: themeService.isDarkMode
                          ? const Color(0xFFffffff)
                          : const Color(0xFF2c3e50),
                      size: 24,
                      weight: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 用户按钮
        SizedBox(
          width: 32,
          height: 32,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  setState(() {
                    _showUserMenu = true;
                  });
                },
                child: Center(
                  child: Icon(
                    LucideIcons.user,
                    color: themeService.isDarkMode
                        ? const Color(0xFFffffff)
                        : const Color(0xFF2c3e50),
                    size: 24,
                    weight: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar(ThemeService themeService) {
    final List<Map<String, dynamic>> navItems = [
      {'icon': LucideIcons.house, 'label': '首页'},
      {'icon': LucideIcons.video, 'label': '电影'},
      {'icon': LucideIcons.tv, 'label': '剧集'},
      {'icon': LucideIcons.cat, 'label': '动漫'},
      {'icon': LucideIcons.clover, 'label': '综艺'},
    ];

    final isTablet = DeviceUtils.isTablet(context);

    return Container(
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF1e1e1e).withOpacity(0.9)
            : Colors.white.withOpacity(0.9),
        border: Border(
          top: BorderSide(
            color: themeService.isDarkMode
                ? const Color(0xFF333333).withOpacity(0.3)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8, // 手动处理底部安全区域
      ),
      child: Row(
        mainAxisAlignment:
            isTablet ? MainAxisAlignment.center : MainAxisAlignment.spaceEvenly,
        children: [
          // 平板模式下添加左侧空白
          if (isTablet) const Spacer(flex: 3),

          // 导航按钮
          ...navItems.asMap().entries.expand((entry) {
            int index = entry.key;
            Map<String, dynamic> item = entry.value;
            bool isSelected =
                !widget.isSearchMode && widget.currentBottomNavIndex == index;

            return [
              GestureDetector(
                onTap: () {
                  widget.onBottomNavChanged(index);
                },
                behavior: HitTestBehavior.opaque, // 确保整个区域都可以点击
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16 : 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item['icon'],
                        color: isSelected
                            ? const Color(0xFF27ae60)
                            : themeService.isDarkMode
                                ? const Color(0xFFb0b0b0)
                                : const Color(0xFF7f8c8d),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['label'],
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF27ae60)
                              : themeService.isDarkMode
                                  ? const Color(0xFFb0b0b0)
                                  : const Color(0xFF7f8c8d),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 平板模式下在按钮之间添加间距
              if (isTablet && index < navItems.length - 1)
                const SizedBox(width: 36),
            ];
          }),

          // 平板模式下添加右侧空白
          if (isTablet) const Spacer(flex: 3),
        ],
      ),
    );
  }
}
