import 'package:bizzy_app/cloud/cloud_service.dart';
import 'package:flutter/material.dart';

/// «Отзывы обо мне»: оценки клиентов + ответ провайдера.
/// У салона — отзывы, оставленные салону.
class ProviderReviewsScreen extends StatefulWidget {
  const ProviderReviewsScreen({super.key});

  @override
  State<ProviderReviewsScreen> createState() => _ProviderReviewsScreenState();
}

class _ProviderReviewsScreenState extends State<ProviderReviewsScreen> {
  final _cloud = CloudService();
  List<ProviderRating> _reviews = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final id = _cloud.uid;
      final reviews = id == null
          ? <ProviderRating>[]
          : await _cloud.ratingsAbout(id);
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _loading = false;
      });
    } catch (e, st) {
      await SyncLog.write('providerReviews', '$e\n$st');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _reply(ProviderRating r) async {
    final controller = TextEditingController(text: r.reply);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ответ на отзыв'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Спасибо за отзыв!..',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (text == null) return;
    try {
      await _cloud.replyToRating(r.id, text);
      if (!mounted) return;
      setState(() {
        final i = _reviews.indexWhere((x) => x.id == r.id);
        if (i >= 0) _reviews[i] = r.copyWith(reply: text);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить ответ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Отзывы обо мне')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Не удалось загрузить отзывы'),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              ),
            )
          : _reviews.isEmpty
          ? const Center(child: Text('Отзывов пока нет'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _reviews.length,
              itemBuilder: (context, i) {
                final r = _reviews[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.clientName.isEmpty ? 'Клиент' : r.clientName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            for (var s = 1; s <= 5; s++)
                              Icon(
                                s <= r.rating ? Icons.star : Icons.star_border,
                                size: 16,
                                color: Colors.amber,
                              ),
                          ],
                        ),
                        if (r.comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(r.comment),
                        ],
                        const SizedBox(height: 8),
                        if (r.reply.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ваш ответ',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(r.reply),
                              ],
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _reply(r),
                              icon: const Icon(Icons.reply, size: 18),
                              label: const Text('Ответить'),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
