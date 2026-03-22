import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';

class _BotItem {
  const _BotItem({required this.id, required this.name, this.avatarUrl});
  final String id;
  final String name;
  final String? avatarUrl;
}

/// Lists available bots and navigates to the companion screen on selection.
class BotPickerScreen extends StatefulWidget {
  const BotPickerScreen({super.key});

  @override
  State<BotPickerScreen> createState() => _BotPickerScreenState();
}

class _BotPickerScreenState extends State<BotPickerScreen> {
  List<_BotItem>? _bots;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBots();
  }

  Future<void> _loadBots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiClient.dio.get<Map<String, dynamic>>('/bots');
      final items = (resp.data?['items'] as List<dynamic>? ?? [])
          .map((e) {
            final m = e as Map<String, dynamic>;
            return _BotItem(
              id: m['id'] as String,
              name: (m['display_name'] as String?) ?? 'Bot',
              avatarUrl: m['avatar_url'] as String?,
            );
          })
          .toList();
      if (mounted) setState(() => _bots = items);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _error = '加载失败：${e.message}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择你的伴伴'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBots,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadBots, child: const Text('重试')),
          ],
        ),
      );
    }
    final bots = _bots ?? [];
    if (bots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('还没有伴伴，请先在管理后台创建 Bot。'),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadBots, child: const Text('刷新')),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _BotCard(bot: bots[i]),
    );
  }
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.bot});
  final _BotItem bot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundImage:
              bot.avatarUrl != null ? NetworkImage(bot.avatarUrl!) : null,
          child: bot.avatarUrl == null
              ? Text(
                  bot.name.isNotEmpty ? bot.name[0] : '?',
                  style: const TextStyle(fontSize: 20),
                )
              : null,
        ),
        title: Text(
          bot.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(
          '/chat/${bot.id}',
          extra: {'botName': bot.name},
        ),
      ),
    );
  }
}
