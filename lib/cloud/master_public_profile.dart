import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_service.dart';

/// Вид публичного профиля мастера: аватар, рейтинг, описание,
/// адрес, соцсети, телефон и список услуг.
/// Используется в клиентской карточке и в предпросмотре мастера.
class MasterPublicProfileView extends StatelessWidget {
  const MasterPublicProfileView({
    super.key,
    required this.master,
    required this.services,
    this.onBook,
    this.isPreview = false,
    this.onRefresh,
  });

  final MasterCard master;
  final List<CloudServiceItem> services;
  final VoidCallback? onBook;
  final bool isPreview;
  final Future<void> Function()? onRefresh;

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    var link = url.trim();
    if (!link.startsWith('http') && !link.startsWith('https')) {
      if (link.startsWith('@')) {
        link = 'https://t.me/${link.substring(1)}';
      } else if (link.contains('t.me/')) {
        link = 'https://$link';
      } else if (link.contains('instagram.com/') ||
          link.contains('instagr.am/')) {
        link = 'https://$link';
      } else if (!link.contains('.')) {
        link = 'https://t.me/$link';
      } else {
        link = 'https://$link';
      }
    }
    final uri = Uri.parse(link);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primary,
              backgroundImage:
                  master.avatarUrl.isNotEmpty ? NetworkImage(master.avatarUrl) : null,
              child: master.avatarUrl.isEmpty
                  ? Icon(Icons.person, color: scheme.onPrimary, size: 36)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    master.name.isEmpty ? 'Мастер' : master.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(master.category),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        master.ratingCount == 0
                            ? 'Пока без оценок'
                            : '${master.ratingAvg.toStringAsFixed(1)} • оценок: ${master.ratingCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (master.address.isNotEmpty) ...[
          _sectionTitle(context, 'Адрес'),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(master.address)),
            ],
          ),
        ],
        if (master.social.isNotEmpty) ...[
          _sectionTitle(context, 'Соцсети'),
          Row(
            children: [
              const Icon(Icons.link_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _openLink(master.social),
                  child: Text(
                    master.social,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (master.phonePublic && master.phone.isNotEmpty) ...[
          _sectionTitle(context, 'Телефон'),
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _call(master.phone),
                  child: Text(
                    master.phone,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (master.description.isNotEmpty) ...[
          _sectionTitle(context, 'О себе'),
          Text(master.description),
        ],
        _sectionTitle(context, 'Услуги'),
        if (services.isEmpty)
          const Text('Услуги ещё не добавлены или не опубликованы'),
        for (final s in services)
          Card(
            child: ListTile(
              leading: const Icon(Icons.spa),
              title: Text(s.name),
              subtitle: Text('${s.durationMinutes} мин'),
              trailing: Text(s.price.toStringAsFixed(0)),
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isPreview ? 'Предпросмотр' : master.name),
      ),
      body: onRefresh == null
          ? content
          : RefreshIndicator(
              onRefresh: onRefresh!,
              child: content,
            ),
      floatingActionButton: onBook == null
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: onBook,
              icon: const Icon(Icons.event_available),
              label: const Text('Записаться'),
            ),
    );
  }
}
