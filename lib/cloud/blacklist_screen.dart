import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:flutter/material.dart';

/// «Чёрный список»: клиенты, которым запрещена запись.
/// Разблокировать можно тут; заблокировать — из карточки клиента.
class BlacklistScreen extends StatefulWidget {
  const BlacklistScreen({super.key});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  final _cloud = CloudService();
  List<({String clientId, String name})> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _cloud.myBlockedClients();
    if (!mounted) return;
    setState(() {
      _blocked = list;
      _loading = false;
    });
  }

  Future<void> _unblock(String clientId) async {
    try {
      await _cloud.unblockClient(clientId);
      if (!mounted) return;
      setState(() => _blocked.removeWhere((c) => c.clientId == clientId));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось разблокировать')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чёрный список')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked.isEmpty
          ? const Center(
              child: Text(
                'Чёрный список пуст.\nЗаблокировать клиента можно '
                'из его карточки.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _blocked.length,
              itemBuilder: (context, i) {
                final c = _blocked[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(c.name.isEmpty ? 'Клиент' : c.name),
                    trailing: TextButton(
                      onPressed: () => _unblock(c.clientId),
                      child: const Text('Разблокировать'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
