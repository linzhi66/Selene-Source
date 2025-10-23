import 'package:flutter/material.dart';
import '../models/live_channel.dart';
import '../services/live_channel_service.dart';
import '../services/user_data_service.dart';
import '../utils/font_utils.dart';
import '../services/theme_service.dart';
import 'package:provider/provider.dart';
import 'live_player_screen.dart';
import '../widgets/live_preview_player.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<LiveChannelGroup> _channelGroups = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedGroup = '全部';

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final groups = await LiveChannelService.getChannelsByGroup();
      
      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _isLoading = false;
          
          if (groups.isEmpty) {
            _errorMessage = '暂无频道，请从 MoonTV 获取';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchFromMoonTV() async {
    final serverUrl = await UserDataService.getServerUrl();
    
    if (serverUrl == null || serverUrl.isEmpty) {
      _showMessage('未配置 MoonTV 服务器地址');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await LiveChannelService.fetchFromMoonTV(serverUrl);
      await _loadChannels();
      
      if (mounted) {
        _showMessage('从 MoonTV 获取成功');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '获取失败: $e';
          _isLoading = false;
        });
        _showMessage('获取失败: $e');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: FontUtils.poppins(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3498DB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  List<LiveChannel> _getFilteredChannels() {
    if (_selectedGroup == '全部') {
      return _channelGroups.expand((g) => g.channels).toList();
    } else if (_selectedGroup == '收藏') {
      return _channelGroups
          .expand((g) => g.channels)
          .where((c) => c.isFavorite)
          .toList();
    } else {
      return _channelGroups
          .firstWhere((g) => g.name == _selectedGroup,
              orElse: () => LiveChannelGroup(name: '', channels: []))
          .channels;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Column(
          children: [
            _buildTopBar(themeService),
            Expanded(
              child: _isLoading
                  ? _buildLoadingView(themeService)
                  : _errorMessage != null
                      ? _buildErrorView(themeService)
                      : _buildChannelList(themeService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(ThemeService themeService) {
    final groups = ['全部', '收藏', ..._channelGroups.map((g) => g.name)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF1e1e1e).withOpacity(0.9)
            : Colors.white.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: themeService.isDarkMode
                ? const Color(0xFF333333).withOpacity(0.3)
                : Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: groups.map((group) {
                  final isSelected = _selectedGroup == group;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedGroup = group;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF27ae60)
                              : themeService.isDarkMode
                                  ? const Color(0xFF2a2a2a)
                                  : const Color(0xFFf5f5f5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          group,
                          style: FontUtils.poppins(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : themeService.isDarkMode
                                    ? const Color(0xFFb0b0b0)
                                    : const Color(0xFF7f8c8d),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            color: const Color(0xFF27ae60),
            tooltip: '刷新直播源',
            onPressed: _fetchFromMoonTV,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF27ae60)),
          ),
          const SizedBox(height: 16),
          Text(
            '加载中...',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: themeService.isDarkMode
                ? const Color(0xFF666666)
                : const Color(0xFF95a5a6),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? '加载失败',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchFromMoonTV,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27ae60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '从 MoonTV 获取',
              style: FontUtils.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(ThemeService themeService) {
    final channels = _getFilteredChannels();

    if (channels.isEmpty) {
      return Center(
        child: Text(
          _selectedGroup == '收藏' ? '暂无收藏频道' : '暂无频道',
          style: FontUtils.poppins(
            color: themeService.isDarkMode
                ? const Color(0xFFb0b0b0)
                : const Color(0xFF7f8c8d),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        double childAspectRatio;
        
        if (constraints.maxWidth < 600) {
          crossAxisCount = 2;
          childAspectRatio = 0.75;
        } else if (constraints.maxWidth < 900) {
          crossAxisCount = 3;
          childAspectRatio = 0.8;
        } else if (constraints.maxWidth < 1200) {
          crossAxisCount = 4;
          childAspectRatio = 0.85;
        } else {
          crossAxisCount = 5;
          childAspectRatio = 0.9;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            return _buildChannelCard(channels[index], themeService);
          },
        );
      },
    );
  }

  Widget _buildChannelCard(LiveChannel channel, ThemeService themeService) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LivePlayerScreen(channel: channel),
          ),
        ).then((_) => _loadChannels());
      },
      child: Container(
        decoration: BoxDecoration(
          color: themeService.isDarkMode
              ? const Color(0xFF1e1e1e)
              : Colors.white,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: LivePreviewPlayer(
                      channel: channel,
                      defaultBuilder: (context) =>
                          _buildDefaultPreview(themeService),
                      enableLivePreview: true, // 默认关闭实时预览，使用 Logo
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () async {
                        await LiveChannelService.toggleFavorite(channel.id);
                        _loadChannels();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          channel.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: channel.isFavorite
                              ? const Color(0xFFe74c3c)
                              : Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Text(
                      channel.title,
                      style: FontUtils.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ).copyWith(
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.8),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: themeService.isDarkMode
                    ? const Color(0xFF2a2a2a)
                    : const Color(0xFFf5f5f5),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: 14,
                    color: themeService.isDarkMode
                        ? const Color(0xFF999999)
                        : const Color(0xFF7f8c8d),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${channel.uris.length} 个源',
                      style: FontUtils.poppins(
                        fontSize: 11,
                        color: themeService.isDarkMode
                            ? const Color(0xFF999999)
                            : const Color(0xFF7f8c8d),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultPreview(ThemeService themeService) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: themeService.isDarkMode
              ? [
                  const Color(0xFF2a2a2a),
                  const Color(0xFF1e1e1e),
                ]
              : [
                  const Color(0xFFe0e0e0),
                  const Color(0xFFf5f5f5),
                ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.tv,
          size: 48,
          color: themeService.isDarkMode
              ? const Color(0xFF666666)
              : const Color(0xFF95a5a6),
        ),
      ),
    );
  }
}
