# ThinStation CI/CD для VMware Horizon VDI

Автоматизированная система сборки загрузочного образа **ThinStation 7.2-ng** с помощью **GitHub Actions**, предварительно настроенного для подключения к серверу виртуализации:

* **Адрес VDI:** `https://vdi.dnestrschool1.online`
* **Платформа сервера:** VMware / Omnissa Horizon (Blast Extreme / PCoIP)
* **Клиент:** Нативный клиент Horizon (`package horizon`)
* **Режим работы:** Kiosk / Полноэкранная сессия с автозапуском
* **Тип загрузки:** Универсальный гибридный ISO (поддерживает как современный **UEFI**, так и классический **Legacy BIOS**)

---

## 📁 Структура репозитория

```text
├── .github/
│   └── workflows/
│       └── build-thinstation.yml   # Workflow для GitHub Actions (автосборка ISO)
├── config/
│   ├── 7.2/                        # Основная стабильная версия ThinStation 7.2 (Fedora 42)
│   │   ├── build.conf              # Список пакетов, драйверов и модулей ядра
│   │   └── thinstation.conf.buildtime # Параметры сессии VDI и настройки ОС
│   └── 6.2/                        # Резервная конфигурация для ветки 6.2-Stable
│       ├── build.conf
│       └── thinstation.conf.buildtime
├── scripts/
│   └── build.sh                    # Скрипт сборщика внутри окружения
├── .gitignore                      # Исключение временных файлов и готовых ISO
└── README.md                       # Инструкция и документация
```

---

## 🚀 Как запустить сборку на GitHub

Вам **не нужно** настраивать локальный Linux или компиляторы — всю работу выполняет облачный раннер GitHub Actions.

### Шаг 1. Отправка файлов в ваш GitHub репозиторий
Выполните в терминале в папке проекта:
```bash
git add .
git commit -m "Configure GitHub Actions build for vdi.dnestrschool1.online"
git push origin main
```

### Шаг 2. Запуск сборки
1. Откройте ваш репозиторий на GitHub: [`https://github.com/Riv33R/Thinstation`](https://github.com/Riv33R/Thinstation).
2. Перейдите во вкладку **Actions** в верхнем меню.
3. В левой колонке выберите воркфлоу **Build Thinstation ISO**.
4. Нажмите кнопку **Run workflow** справа:
   * Выберите ветку `main`.
   * Выберите версию ThinStation: `7.2-Stable` (по умолчанию).
   * Нажмите зеленую кнопку **Run workflow**.

### Шаг 3. Скачивание готового ISO
* Процесс сборки длится обычно **15–25 минут** (скачиваются пакеты ядра, драйверы, среда Horizon и компилируется ISO-образ).
* После успешного завершения откройте выполненный запуск сборки.
* Внизу страницы в разделе **Artifacts** появится архив **`thinstation-7.2-Stable-iso`**.
* Скачайте его и распакуйте — внутри будет готовый загрузочный файл:
  * `thinstation-efi.iso` (гибридный ISO для флешек и CD).

---

## 💾 Запись образа на USB-флешку

### Способ 1. Ventoy (Самый удобный и рекомендуемый)
1. Установите [Ventoy](https://www.ventoy.net/) на вашу флешку.
2. Просто скопируйте полученный `.iso` файл в корень флешки.
3. Вставьте флешку в ПК/тонкий клиент и загрузитесь с неё (поддерживаются любые типы загрузки UEFI и BIOS).

### Способ 2. Rufus
1. Скачайте и запустите [Rufus](https://rufus.ie/).
2. Выберите вашу USB-флешку и файл `thinstation-efi.iso`.
3. При запросе режима записи выберите **Режим DD** (или гибридный ISO-образ).
4. Нажмите **Старт**.

---

## ⚙️ Настройки и кастомизация

Все настройки подключения к серверу VDI находятся в файле [`config/7.2/thinstation.conf.buildtime`](config/7.2/thinstation.conf.buildtime):

| Параметр | Значение | Описание |
| :--- | :--- | :--- |
| `SESSION_0_TYPE` | `horizon` | Использование нативного клиента VMware/Omnissa Horizon |
| `SESSION_0_HORIZON_SERVERURL` | `https://vdi.dnestrschool1.online` | Адрес сервера подключения VDI |
| `SESSION_0_AUTOSTART` | `On` | Автоматический запуск сессии при включении клиента |
| `SESSION_0_HORIZON_FULLSCREEN` | `true` | Полноэкранный режим без лишних рамок |
| `SESSION_0_HORIZON_NONINTERACTIVE` | `false` | Отображение окна входа для ввода логина и пароля пользователя |
| `HORIZON_SSLVERIFYMODE` | `1` | Проверка валидности SSL-сертификата сервера |
| `KEYBOARD_MAP` / `XKEYBOARD` | `ru` / `"us,ru"` | Раскладки US и RU, переключение по `Alt + Shift` |
| `AUDIO_LEVEL` | `85` | Громкость звука по умолчанию |
| `USB_STORAGE_SYNC` | `on` | Поддержка и проброс пользовательских USB-флешек |

Если потребуется включить дополнительные видеодрайверы или компоненты, отредактируйте [`config/7.2/build.conf`](config/7.2/build.conf). Любой последующий `git push` позволит пересобрать обновленный образ.

---

## 🖥️ Локальная сборка (Опционально через Docker / WSL)

Если вы хотите собрать образ локально на компьютере с установленным Docker (или в WSL2):

```bash
docker run --privileged --rm -v ${PWD}:/workspace fedora:42 /bin/bash -c "
  dnf install -y git dnf coreutils findutils procps-ng util-linux tar xz gzip dbus-tools which
  chmod +x /workspace/scripts/build.sh
  /workspace/scripts/build.sh 7.2-Stable /workspace
"
```
Готовые файлы появятся в локальной папке `./output/`.
