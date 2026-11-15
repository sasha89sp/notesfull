part of 'connect.dart';

extension _ExtConnectScreenState2 on _ConnectScreenState {

  List<Widget> _stepFolder(Color sec) => [
        Text('Выберите папку с данными ASRbox или создайте новую.',
            style: TextStyle(color: sec, fontSize: 13)),
        const SizedBox(height: 8),
        if (_dirs.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in _dirs)
                  ListTile(
                    dense: true,
                    leading: Icon(_picked == d ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: Text(d),
                    onTap: () => setState(() => _picked = d),
                  ),
              ],
            ),
          ),
        ListTile(
          dense: true,
          leading: Icon(_picked == null ? Icons.radio_button_checked : Icons.radio_button_off),
          title: const Text('Новая папка'),
          onTap: () => setState(() => _picked = null),
        ),
        if (_picked == null)
          TextField(
              controller: _newFolder,
              decoration: const InputDecoration(labelText: 'Название новой папки')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step = 0),
                  child: const Text('Назад'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : _toAccount, child: const Text('Далее'))),
        ]),
      ];

  List<Widget> _stepAccount(Color sec) => [
        Text(
            'Придумайте логин и пароль ASRbox или войдите с уже существующими. '
            'Данные каждого пользователя шифруются его паролем и недоступны остальным, '
            'даже если все используют один WebDAV. Пароль восстановить нельзя.',
            style: TextStyle(color: sec, fontSize: 13)),
        const SizedBox(height: 12),
        if (_legacyAvail)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Данные старой версии'),
            subtitle: const Text('В папке есть профиль без аккаунтов (MySecureApp)',
                style: TextStyle(fontSize: 12)),
            value: _legacy,
            onChanged: (v) => setState(() => _legacy = v),
          ),
        TextField(controller: _login, decoration: const InputDecoration(labelText: 'Логин')),
        const SizedBox(height: 10),
        TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль (от 8 символов)')),
        if (_askRepeat) ...[
          const SizedBox(height: 10),
          TextField(
              controller: _pw2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Повторите пароль')),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text('Запомнить на этом устройстве'),
          value: _remember,
          onChanged: (v) => setState(() => _remember = v ?? false),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step = 1),
                  child: const Text('Назад'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : _enter,
                  child: Text(_askRepeat ? 'Создать аккаунт' : 'Войти'))),
        ]),
      ];
}
