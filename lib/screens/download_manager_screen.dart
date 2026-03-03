import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:selene/design/design_system.dart';
import 'package:selene/models/download_task_record.dart';
import 'package:selene/screens/player_screen.dart';
import 'package:selene/services/download_manager_service.dart';
import 'package:selene/utils/font_utils.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DownloadManagerService _downloadManager;
  Timer? _refreshTimer;
  Map<String, StreamSubscription<DownloadProgressInfo>> _progressSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _downloadManager = DownloadManagerService();
    _downloadManager.init().then((_) {
      _subscribeToAllTasks();
    });
    _tabController = TabController(length: 4, vsync: this);
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _subscribeToAllTasks() {
    final tasks = _downloadManager.getAllTasks();
    for (final task in tasks) {
      if (task.isDownloading && !_progressSubscriptions.containsKey(task.taskId)) {
        final stream = _downloadManager.getProgressStream(task.taskId);
        if (stream != null) {
          _progressSubscriptions[task.taskId] = stream.listen((_) {
            if (mounted) setState(() {});
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final sub in _progressSubscriptions.values) {
      sub.cancel();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChangeNotifierProvider.value(
      value: _downloadManager,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: _buildAppBar(isDark),
        body: Column(
          children: [
            _buildTabBar(isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTaskList(isDark, 'downloading'),
                  _buildTaskList(isDark, 'paused'),
                  _buildTaskList(isDark, 'completed'),
                  _buildTaskList(isDark, 'failed'),
                ],
              ),
            ),
            _buildBottomActions(isDark),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          LucideIcons.arrowLeft,
          color: isDark ? Colors.white : Colors.black87,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        '下载管理',
        style: FontUtils.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            LucideIcons.settings,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          onPressed: () => _showSettingsMenu(context),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
        indicatorColor: AppColors.primary,
        labelStyle: FontUtils.poppins(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: [
          Tab(text: '下载中 (${_downloadManager.downloadingCount})'),
          Tab(text: '已暂停 (${_downloadManager.pausedCount})'),
          Tab(text: '已完成 (${_downloadManager.completedCount})'),
          Tab(text: '失败 (${_downloadManager.failedCount})'),
        ],
      ),
    );
  }

  List<DownloadTaskRecord> _getFilteredTasks(String filter) {
    final allTasks = _downloadManager.getAllTasks();
    switch (filter) {
      case 'downloading':
        return allTasks.where((t) => t.isDownloading || t.isPending).toList();
      case 'paused':
        return allTasks.where((t) => t.isPaused).toList();
      case 'completed':
        return allTasks.where((t) => t.isCompleted).toList();
      case 'failed':
        return allTasks.where((t) => t.isFailed).toList();
      default:
        return allTasks;
    }
  }

  Widget _buildTaskList(bool isDark, String filter) {
    final tasks = _getFilteredTasks(filter);
    if (tasks.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = _downloadManager.getTask(tasks[index].taskId) ?? tasks[index];
        return _buildTaskItem(isDark, task);
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.download,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: FontUtils.poppins(
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(bool isDark, DownloadTaskRecord task) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        children: [
          _buildTaskHeader(isDark, task),
          _buildTaskProgress(isDark, task),
          _buildTaskActions(isDark, task),
        ],
      ),
    );
  }

  Widget _buildTaskHeader(bool isDark, DownloadTaskRecord task) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildTaskCover(task),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.videoTitle ?? task.fileName,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  task.episodeInfo ?? task.fileName,
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task.displaySize,
                  style: FontUtils.poppins(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusChip(isDark, task),
        ],
      ),
    );
  }

  Widget _buildTaskCover(DownloadTaskRecord task) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: task.coverUrl != null
          ? CachedNetworkImage(
              imageUrl: task.coverUrl!,
              width: 60,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 60,
                height: 80,
                color: Colors.grey[300],
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 60,
                height: 80,
                color: Colors.grey[300],
                child: const Icon(Icons.video_file, color: Colors.grey),
              ),
            )
          : Container(
              width: 60,
              height: 80,
              color: Colors.grey[300],
              child: const Icon(Icons.video_file, color: Colors.grey),
            ),
    );
  }

  Widget _buildStatusChip(bool isDark, DownloadTaskRecord task) {
    Color bgColor;
    Color textColor;
    String label;

    if (task.isDownloading) {
      bgColor = AppColors.primary.withValues(alpha: 0.1);
      textColor = AppColors.primary;
      label = '下载中';
    } else if (task.isPaused) {
      bgColor = Colors.orange.withValues(alpha: 0.1);
      textColor = Colors.orange;
      label = '已暂停';
    } else if (task.isCompleted) {
      bgColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green;
      label = '已完成';
    } else if (task.isFailed) {
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = Colors.red;
      label = '失败';
    } else {
      bgColor = Colors.grey.withValues(alpha: 0.1);
      textColor = Colors.grey;
      label = '等待中';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: FontUtils.poppins(fontSize: 11, color: textColor),
      ),
    );
  }

  Widget _buildTaskProgress(bool isDark, DownloadTaskRecord task) {
    if (task.isCompleted) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(
                task.isFailed ? Colors.red : AppColors.primary,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                task.displayProgress,
                style: FontUtils.poppins(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              if (task.totalSegments != null && task.totalSegments! > 0)
                Text(
                  '${task.currentSegmentIndex ?? 0}/${task.totalSegments}',
                  style: FontUtils.poppins(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskActions(bool isDark, DownloadTaskRecord task) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _buildActionButtons(isDark, task),
      ),
    );
  }

  List<Widget> _buildActionButtons(bool isDark, DownloadTaskRecord task) {
    final buttons = <Widget>[];

    if (task.isDownloading) {
      buttons.add(_buildActionButton(
        icon: LucideIcons.pause,
        label: '暂停',
        isDark: isDark,
        onPressed: () => _downloadManager.pauseTask(task.taskId),
      ));
    }

    if (task.isPaused || task.isFailed) {
      buttons.add(_buildActionButton(
        icon: LucideIcons.play,
        label: '继续',
        isDark: isDark,
        onPressed: () {
          _downloadManager.resumeTask(task.taskId);
          _subscribeToTask(task.taskId);
        },
      ));
    }

    if (task.isCompleted) {
      buttons.add(_buildActionButton(
        icon: LucideIcons.play,
        label: '播放',
        isDark: isDark,
        onPressed: () => _playVideo(task),
        highlight: true,
      ));
      buttons.add(_buildActionButton(
        icon: LucideIcons.folder,
        label: '打开',
        isDark: isDark,
        onPressed: () => _openFile(task),
      ));
    }

    if (task.isFailed && task.errorMessage != null) {
      buttons.add(_buildActionButton(
        icon: LucideIcons.info,
        label: '详情',
        isDark: isDark,
        onPressed: () => _showErrorDetails(task),
      ));
    }

    buttons.add(_buildActionButton(
      icon: LucideIcons.trash2,
      label: '删除',
      isDark: isDark,
      isDestructive: true,
      onPressed: () => _confirmDelete(task),
    ));

    return buttons;
  }

  void _subscribeToTask(String taskId) {
    if (!_progressSubscriptions.containsKey(taskId)) {
      final stream = _downloadManager.getProgressStream(taskId);
      if (stream != null) {
        _progressSubscriptions[taskId] = stream.listen((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onPressed,
    bool isDestructive = false,
    bool highlight = false,
  }) {
    Color bgColor;
    Color textColor;

    if (isDestructive) {
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = Colors.red;
    } else if (highlight) {
      bgColor = AppColors.primary.withValues(alpha: 0.1);
      textColor = AppColors.primary;
    } else {
      bgColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
      textColor = isDark ? Colors.white70 : Colors.black54;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: textColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: FontUtils.poppins(fontSize: 12, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: _buildBottomButton(
                icon: LucideIcons.pause,
                label: '全部暂停',
                isDark: isDark,
                onPressed: () => _downloadManager.pauseAll(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBottomButton(
                icon: LucideIcons.play,
                label: '全部继续',
                isDark: isDark,
                onPressed: () {
                  _downloadManager.resumeAll();
                  _subscribeToAllTasks();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBottomButton(
                icon: LucideIcons.refreshCw,
                label: '重试失败',
                isDark: isDark,
                onPressed: () {
                  _downloadManager.retryAllFailed();
                  _subscribeToAllTasks();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: FontUtils.poppins(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(LucideIcons.check, color: AppColors.primary),
              title: Text('清除已完成', style: FontUtils.poppins()),
              onTap: () {
                Navigator.pop(context);
                _downloadManager.clearCompletedTasks();
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.x, color: Colors.red),
              title: Text('清除失败任务', style: FontUtils.poppins()),
              onTap: () {
                Navigator.pop(context);
                _downloadManager.clearFailedTasks();
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: Colors.red[400]),
              title: Text('清除全部任务', style: FontUtils.poppins()),
              onTap: () {
                Navigator.pop(context);
                _confirmClearAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(DownloadTaskRecord task) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定要删除 "${task.videoTitle ?? task.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadManager.deleteTask(task.taskId);
            },
            child: const Text('仅删除任务'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadManager.deleteTask(task.taskId, deleteFile: true);
            },
            child: const Text('删除任务和文件', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部任务'),
        content: const Text('确定要清除所有下载任务吗？这不会删除已下载的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadManager.clearCompletedTasks();
              _downloadManager.clearFailedTasks();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _playVideo(DownloadTaskRecord task) {
    final file = File(task.filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件不存在')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerScreen(
          title: task.videoTitle ?? task.fileName,
          localFilePath: task.filePath,
        ),
      ),
    );
  }

  void _openFile(DownloadTaskRecord task) async {
    final file = File(task.filePath);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
      }
      return;
    }

    final uri = Uri.file(task.filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件保存在: ${task.filePath}')),
      );
    }
  }

  void _showErrorDetails(DownloadTaskRecord task) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误详情'),
        content: SingleChildScrollView(
          child: Text(task.errorMessage ?? '未知错误'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
