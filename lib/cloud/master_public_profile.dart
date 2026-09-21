import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'cloud_service.dart';

/// Вид публичного профиля мастера: аватар, рейтинг, описание,
/// адрес, соцсети, телефон и список услуг.
/// Используется в клиентской карточке и в предпросмотре мастера.
class MasterPublicProfileView extends StatelessWidget {
  const MasterPublicProfileView({
    super.key,
    required this.master,
    required this.services,
    this.portfolio = const [],
    this.offers = const [],
    this.onBook,
    this.onBookService,
    this.onBookOffer,
    this.isPreview = false,
    this.onRefresh,
    this.isFavorite,
    this.onToggleFavorite,
  });

  final MasterCard master;
  final List<CloudServiceItem> services;

  /// Фото работ мастера — сетка в разделе «Работы мастера».
  final List<PortfolioPhoto> portfolio;

  /// Актуальные Honey провайдера — блок «Honey» в профиле.
  final List<SalonOffer> offers;
  final VoidCallback? onBook;

  /// Тап по услуге — сразу диалог записи с выбранной услугой.
  final void Function(CloudServiceItem service)? onBookService;

  /// Тап по Honey — диалог записи с применённой скидкой.
  final void Function(SalonOffer offer)? onBookOffer;
  final bool isPreview;
  final Future<void> Function()? onRefresh;

  /// null — сердечко избранного не показываем (предпросмотр мастера).
  final bool? isFavorite;
  final VoidCallback? onToggleFavorite;

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
              // Тап по услуге → сразу запись с ней.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.price.toStringAsFixed(0)),
                  if (onBookService != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.event_available,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ],
              ),
              onTap: onBookService == null
                  ? null
                  : () => onBookService!(s),
            ),
          ),
        if (offers.isNotEmpty) ...[
          _sectionTitle(context, 'Honey'),
          for (final o in offers)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: o.used || onBookOffer == null
                    ? null
                    : () => onBookOffer!(o),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (o.imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            o.imageUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => Icon(
                              Icons.card_giftcard,
                              color: scheme.primary,
                            ),
                          ),
                        )
                      else
                        Icon(Icons.card_giftcard, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    decoration: o.used
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: o.used
                                        ? scheme.outline
                                        : null,
                                  ),
                            ),
                            Text(
                              [
                                if (o.value.isNotEmpty) o.value,
                                if (o.discountPercent > 0)
                                  '−${o.discountPercent == o.discountPercent.roundToDouble() ? o.discountPercent.toStringAsFixed(0) : o.discountPercent.toStringAsFixed(1)}%',
                              ].join(' · '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (o.used)
                        Text(
                          'Использовано',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.outline),
                        )
                      else if (onBookOffer != null)
                        Icon(
                          Icons.chevron_right,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (portfolio.isNotEmpty) ...[
          _sectionTitle(context, 'Работы мастера'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final photo in portfolio)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photo.imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : Container(
                                color: scheme.surfaceContainerHighest,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
        actions: [
          if (isFavorite != null && onToggleFavorite != null)
            IconButton(
              tooltip: 'Избранное',
              icon: Icon(
                isFavorite! ? Icons.favorite : Icons.favorite_border,
                color: isFavorite! ? Colors.redAccent : null,
              ),
              onPressed: onToggleFavorite,
            ),
        ],
      ),
      body: onRefresh == null
          ? content
          : RefreshIndicator(
              onRefresh: onRefresh!,
              child: content,
            ),
      floatingActionButton: onBook == null
          ? null
          : bizzyFab(
              onPressed: onBook,
              icon: Icons.event_available,
              label: 'Записаться',
            ),
    );
  }
}
