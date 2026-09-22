import 'package:flutter/material.dart';

import 'cloud_service.dart';

/// Диалог «Изменить логин и пароль» — одинаковый для клиента,
/// мастера и салона. Логин предзаполнен текущим; пароль можно
/// оставить пустым, тогда меняется только логин.
Future<void> showCredentialsEditor(BuildContext context) async {
  final cloud = CloudService();
  final loginCtrl = TextEditingController(text: cloud.displayLogin);
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Логин и пароль'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: loginCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Логин',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Введите логин' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Новый пароль',
                hintText: 'Пусто — не менять',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v != null && v.isNotEmpty && v.length < 6)
                  ? 'Минимум 6 символов'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Повторите новый пароль',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v != newCtrl.text ? 'Пароли не совпадают' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(dialogContext).pop(true);
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );

  final login = loginCtrl.text.trim();
  final password = newCtrl.text;
  loginCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();

  if (ok != true || !context.mounted) return;

  final needLogin = login.isNotEmpty && login != cloud.displayLogin;
  if (!needLogin && password.isEmpty) return;
  try {
    await cloud.updateAuth(
      login: needLogin ? login : null,
      password: password.isNotEmpty ? password : null,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Данные для входа обновлены')));
  } catch (e) {
    await SyncLog.write('credentials', e.toString());
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Не удалось обновить данные')));
  }
}
