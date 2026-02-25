import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../services/m3u8_download_service.dart';
import '../utils/device_utils.dart';
import '../screens/local_player_screen.dart';

class DownloadPanel extends StatefulWidget {
  final VoidCallback? onClose;

  const DownloadPanel({super.key, this.onClose});

  @override
  State<DownloadPanel> createState() => _DownloadPanelState();
}

class _DownloadPanelState extends State<DownloadPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _buildHeader(theme, isDarkMode),
          const Divider(height: 1),
          Expanded(
            child: Consumer<M3U8DownloadService>(
              builder: (context, service, child) {
                if (service.tasks.isEmpty) {
                  return _buildEmptyState(theme, isDarkMode);
                }
                return _buildTaskList(theme, isDarkMode, service);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '下载管理',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          Consumer<M3U8DownloadService>(
            builder: (context, service, child) {
              if (service.completedTasks.isNotEmpty) {
                return TextButton(
                  onPressed: () => service.clearCompletedTasks(),
                  child: Text(
                    '清除已完成',
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              icon: Icon(
                Icons.close,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在播放页面点击下载按钮开始下载',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(ThemeData theme, bool isDarkMode, M3U8DownloadService service) {
    final tasks = service.tasks.toList();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return _DownloadTaskItem(
          task: tasks[index],
          isDarkMode: isDarkMode,
          theme: theme,
        );
      },
    );
  }
}

class _DownloadTaskItem extends StatelessWidget {
  final DownloadTask task;
  final bool isDarkMode;
  final ThemeData theme;

  const _DownloadTaskItem({
    required this.task,
    required this.isDarkMode,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除下载任务'),
            content: Text('确定要删除 "${task.title}" 的下载任务吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        final service = context.read<M3U8DownloadService>();
        service.deleteTask(task.id, deleteFile: task.status == DownloadStatus.completed);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleRow(context),
              const SizedBox(height: 8),
              _buildProgressSection(),
              const SizedBox(height: 8),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${task.episodeTitle} · ${task.sourceName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        _buildStatusChip(),
      ],
    );
  }

  Widget _buildStatusChip() {
    Color chipColor;
    Color textColor;
    
    switch (task.status) {
      case DownloadStatus.pending:
        chipColor = Colors.grey.withOpacity(0.2);
        textColor = Colors.grey;
        break;
      case DownloadStatus.downloading:
        chipColor = Colors.blue.withOpacity(0.2);
        textColor = Colors.blue;
        break;
      case DownloadStatus.paused:
        chipColor = Colors.orange.withOpacity(0.2);
        textColor = Colors.orange;
        break;
      case DownloadStatus.completed:
        chipColor = Colors.green.withOpacity(0.2);
        textColor = Colors.green;
        break;
      case DownloadStatus.failed:
        chipColor = Colors.red.withOpacity(0.2);
        textColor = Colors.red;
        break;
      case DownloadStatus.cancelled:
        chipColor = Colors.grey.withOpacity(0.2);
        textColor = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        task.statusText,
        style: TextStyle(
          fontSize: 12,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: task.progress,
            backgroundColor: isDarkMode ? Colors.grey[700] : Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              task.status == DownloadStatus.failed ? Colors.red : Colors.green,
            ),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${task.downloadedSegments}/${task.totalSegments} 片段',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            Text(
              task.progressText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            task.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.red,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final service = context.read<M3U8DownloadService>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (task.status == DownloadStatus.downloading)
          _ActionButton(
            icon: Icons.pause,
            label: '暂停',
            isDarkMode: isDarkMode,
            onPressed: () => service.pauseDownload(task.id),
          ),
        if (task.status == DownloadStatus.paused || task.status == DownloadStatus.pending)
          _ActionButton(
            icon: Icons.play_arrow,
            label: '继续',
            isDarkMode: isDarkMode,
            onPressed: () => service.resumeDownload(task.id),
          ),
        if (task.status == DownloadStatus.failed)
          _ActionButton(
            icon: Icons.refresh,
            label: '重试',
            isDarkMode: isDarkMode,
            onPressed: () => service.resumeDownload(task.id),
          ),
        if (task.status == DownloadStatus.completed) ...[
          _ActionButton(
            icon: Icons.play_circle_filled,
            label: '播放',
            isDarkMode: isDarkMode,
            onPressed: () => _playVideo(context),
          ),
          if (DeviceUtils.isPC())
            _ActionButton(
              icon: Icons.folder_open,
              label: '打开',
              isDarkMode: isDarkMode,
              onPressed: () => _openFile(context),
            ),
        ],
      ],
    );
  }

  void _playVideo(BuildContext context) async {
    try {
      final file = File(task.savePath);
      if (await file.exists()) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LocalPlayerScreen(
              filePath: task.savePath,
              title: task.title,
              episodeTitle: task.episodeTitle,
              cover: task.cover,
            ),
          ),
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在，可能已被删除')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  void _openFile(BuildContext context) async {
    try {
      final file = File(task.savePath);
      if (await file.exists()) {
        if (DeviceUtils.isPC()) {
          if (Platform.isWindows) {
            Process.run('explorer', ['/select,', task.savePath]);
          } else if (Platform.isMacOS) {
            Process.run('open', ['-R', task.savePath]);
          } else if (Platform.isLinux) {
            Process.run('xdg-open', [task.savePath]);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件失败: $e')),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDarkMode;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDarkMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
