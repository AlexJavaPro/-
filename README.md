# ФотоПочта

Легкое Android-приложение для отправки большого количества фото через внешние почтовые приложения (по умолчанию Яндекс Почта), без входа и паролей внутри приложения.

## Что делает приложение

- Выбирает сразу много фото из системного пикера.
- Считает размер каждого файла и общий объем.
- Делит вложения на письма по лимиту (например, 20 МБ на письмо).
- Позволяет отправлять диапазон частей: `С части` / `По часть`.
- Формирует тему с датой отчета: `Фото от dd.MM.yyyy (Часть X из Y)`.
- Добавляет в текст письма список файлов и количество.
- Открывает внешнее почтовое приложение через системный `Share/Intent`.

## Что важно по безопасности

- Приложение не хранит и не запрашивает пароль от почты.
- Отправка выполняется через выбранный внешний почтовый клиент.
- В настройках можно выбрать предпочтительный клиент (по умолчанию Яндекс Почта).

## Интерфейс и UX

- Без popup-диалогов в основном сценарии отправки.
- Статусы и ошибки показываются inline внизу экрана.
- Дата отчета по умолчанию текущая, изменение только через системный `Date Picker`.
- После возврата из почтового клиента экран остается на блоке отправки (внизу).

## Иконка и имя приложения

- Имя приложения (Android): `ФотоПочта`.
- Исходник иконки: `assets/icons/app_icon.png`.
- Генерация launcher-иконок:

```powershell
dart run flutter_launcher_icons
```

## Запуск и сборка

```powershell
flutter pub get
flutter run
```

Сборка APK:

```powershell
flutter build apk --debug
```

Готовый APK:

`build\app\outputs\flutter-apk\app-debug.apk`

## Проверка качества

```powershell
flutter analyze
flutter test
flutter pub outdated
```

## Branding Build Checks (Android)

Branding source of truth:

- App name: `android/app/src/main/res/values/strings.xml` (`app_name=ФотоПочта`)
- Launcher icon source: `assets/icons/app_icon.png`

Release branding pipeline:

```powershell
flutter pub get
dart run flutter_launcher_icons
powershell -ExecutionPolicy Bypass -File .\scripts\check_android_branding.ps1
flutter build apk --release
powershell -ExecutionPolicy Bypass -File .\scripts\check_android_branding.ps1 -RequireBuiltApk
```

What is validated:

- `AndroidManifest.xml` uses `@string/app_name`
- `AndroidManifest.xml` uses `@mipmap/ic_launcher` for `icon` and `roundIcon`
- `mipmap-*` folders contain `ic_launcher.*`
- `mipmap-anydpi-v26/ic_launcher.xml` exists
