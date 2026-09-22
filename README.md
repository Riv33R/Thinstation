# ThinStation CI/CD для Omnissa / VMware Horizon VDI

Автоматизированная система сборки тонкого клиента на базе **ThinStation 7.2-ng** с помощью **GitHub Actions**, предварительно сконфигурированного для работы с инфраструктурой виртуальных рабочих столов (VDI):

* **Адрес VDI:** `https://vdi.dnestrschool1.online`
* **Платформа сервера:** Omnissa / VMware Horizon (протоколы Blast Extreme и PCoIP)
* **Клиент:** Нативный клиент Omnissa Horizon Client 2506 (8.16.0)
* **Режим работы:** Двухуровневый Kiosk-режим (рабочий стол XFCE + автозапуск полноэкранной сессии VDI)
* **Поддержка мультимониторов:** Автоматическое расширение рабочего стола на все подключенные экраны (Extended Desktop)
* **Сетевые возможности:** Поддержка Ethernet и Wi-Fi с графическим меню выбора сетей в трее (`nm-applet`)
* **Поддержка ноутбуков:** Тачпады с жестами и кликом касанием (Tap-to-click)
* **Тип загрузки:** Универсальный гибридный ISO (поддержка **UEFI 64-bit** и классического **Legacy BIOS**)

---

## 📁 Структура репозитория

```text
├── .github/
│   └── workflows/
│       └── build-thinstation.yml   # Workflow для GitHub Actions (автосборка ISO в облаке)
├── config/
│   ├── 7.2/                        # Основная стабильная версия ThinStation 7.2 (на базе Fedora 42)
│   │   ├── build.conf              # Список пакетов, видеодрайверов и модулей ядра
│   │   └── thinstation.conf.buildtime # Параметры сессии VDI, XRandR, раскладки и сети
│   └── 6.2/                        # Резервная конфигурация для ветки ThinStation 6.2
│       ├── build.conf
│       └── thinstation.conf.buildtime
├── scripts/
│   └── build.sh                    # Скрипт сборки chroot, интеграции Horizon и патчей
├── .gitignore                      # Исключение временных файлов и готовых ISO
└── README.md                       # Документация и руководство пользователя
```

---

## 🚀 Как запустить сборку на GitHub

Сборка происходит полностью в облачной инфраструктуре GitHub Actions без необходимости устанавливать Linux локально.

### Шаг 1. Отправка изменений в репозиторий
Выполните в терминале рабочей директории:
```bash
git add .
git commit -m "Update configuration"
git push origin main
```

### Шаг 2. Запуск сборки
1. Откройте репозиторий на GitHub: [`https://github.com/Riv33R/Thinstation`](https://github.com/Riv33R/Thinstation).
2. Перейдите во вкладку **Actions** в верхнем меню.
3. В левой колонке выберите воркфлоу **Build Thinstation ISO**.
4. Нажмите кнопку **Run workflow** справа:
   * Ветка: `main`.
   * Версия: `7.2-Stable` (по умолчанию).
   * Нажмите зеленую кнопку **Run workflow**.

### Шаг 3. Скачивание готового ISO
* Сборка занимает около **15–20 минут** (компиляция ядра, сборка squashfs и генерация ISO).
* По завершении процесса откройте выполненный запуск сборки.
* Внизу страницы в блоке **Artifacts** скачайте архив **`thinstation-7.2-Stable-iso`**.
* Внутри архива находится готовый загрузочный файл:
  * `thinstation-efi.iso` (гибридный ISO для USB-флешек и компакт-дисков).

---

## 💾 Запись образа на USB-флешку

### Способ 1. Ventoy (Рекомендуется)
1. Установите [Ventoy](https://www.ventoy.net/) на USB-накопитель.
2. Скопируйте файл `thinstation-efi.iso` на флешку.
3. Загрузите тонкий клиент или ПК с этой флешки.

### Способ 2. Rufus
1. Скачайте и запустите [Rufus](https://rufus.ie/).
2. Выберите вашу флешку и файл `thinstation-efi.iso`.
3. При запросе типа записи обязательно выберите **Режим DD** (или гибридный ISO-образ).
4. Нажмите **Старт**.

---

## 🖥️ Ключевые возможности и конфигурация

### 1. Архитектура рабочих сессий
Для обеспечения стабильной работы D-Bus, апплета Wi-Fi и Horizon Client используется разделение на две сессии:
* **`SESSION_0` (XFWM4 / XFCE):** Легковесное графическое окружение, нижняя панель задач с системным треем, апплетом громкости и сетевым менеджером `nm-applet`.
* **`SESSION_1` (Omnissa Horizon):** Запускается от имени пользователя `tsuser` с доступом к пользовательской шине D-Bus и сохраненному Machine ID. При запуске клиент автоматически инициирует соединение с сервером `https://vdi.dnestrschool1.online`.

### 2. Поддержка нескольких мониторов (Multi-Monitor Extended Desktop)
* **Автоматическое позиционирование:** При старте системы запускается утилита `/bin/auto-multimonitor`, которая через `xrandr` находит все подключенные мониторы и объединяет их в единый широкий рабочий стол слева направо (`--right-of`), назначая первый экран основным.
* **Сессия Horizon на всех экранах:** В настройках клиента включены `SESSION_1_HORIZON_ALLMONITORS=true` и `view.defaultDesktopSize = "1"`. Сессия виртуального рабочего стола растягивается на все физические экраны пользователя.
* **Переключение окон:** Включен параметр `SESSION_1_HORIZON_KEEP_WM_BINDINGS=true` — пользователь в любой момент может нажать `Alt + Tab` или клавишу `Super` (Windows) для доступа к локальной панели задач и трею.

### 3. Сеть и подключение Wi-Fi на ноутбуках
* **Сетевой стек:** Используется **NetworkManager** с собственным внутренним DHCP-клиентом (`dhcp=internal`).
* **Быстрая загрузка:** Блокирующая служба `NetworkManager-wait-online` отключена — система загружается в графический интерфейс за 3–5 секунд без 90-секундных зависаний при отсутствии кабеля сети.
* **Графический апплет:** В правом нижнем углу экрана отображается иконка **`nm-applet`**. Клик левой кнопкой мыши открывает список доступных сетей Wi-Fi для ввода пароля и подключения.
* **Драйверы:** В ядро включены драйверы для популярных Wi-Fi чипов:
  * Intel Wireless (`iwlwifi`, `iwlmvm`, `iwldvm`)
  * Realtek (`rtw88`, `rtw89`, `r8188eu`, `rtl8xxxu`)
  * MediaTek (`mt7921e`, `mt76`)
  * Atheros / Qualcomm (`ath9k`, `ath10k_pci`, `ath11k_pci`)
  * Broadcom (`brcmfmac`)

### 4. Поддержка тачпада на ноутбуках
* Включены драйверы `xorg7-xinput` (модуль `libinput`), `psmouse`, `i2c-hid`, `i2c-hid-acpi`, `hid-multitouch`, `intel-lpss` и `elan_i2c`.
* Создана конфигурация `/etc/X11/xorg.conf.d/30-touchpad.conf` с включенным **Tap-to-click** (нажатие легким касанием по сенсорной панели) и двухпальцевым кликом для правой кнопки мыши.

---

## ⚙️ Справочник параметров конфигурации

Основные настройки содержатся в файле [`config/7.2/thinstation.conf.buildtime`](config/7.2/thinstation.conf.buildtime):

| Параметр | Значение | Назначение |
| :--- | :--- | :--- |
| `SESSION_0_TYPE` | `xfwm4` | Запуск оконного менеджера и панели задач XFCE |
| `SESSION_0_AUTOSTART` | `on` | Автоматический старт окружения рабочего стола |
| `SESSION_1_TYPE` | `horizon` | Тип сессии — нативный клиент Omnissa/VMware Horizon |
| `SESSION_1_TITLE` | `VDI` | Заголовок и идентификатор сессии |
| `SESSION_1_HORIZON_SERVERURL` | `https://vdi.dnestrschool1.online` | Адрес сервера VDI Horizon |
| `HORIZON_DEFAULTBROKER` | `https://vdi.dnestrschool1.online` | Предзаполненный адрес сервера в клиенте Horizon |
| `HORIZON_AUTOCONNECT` | `TRUE` | Автоматический переход к окну ввода логина/пароля без выбора сервера вручную |
| `HORIZON_SSLVERIFYMODE` | `3` | Режим проверки SSL (не прерывает соединение при расхождениях времени или нехватке CA) |
| `USE_XRANDR` | `true` | Использование подсистемы XRandR для управления дисплеями |
| `XRANDR_OPTIONS` | `"--auto"` | Автоматическое выставление родного разрешения экранов |
| `SET_RESOLUTION_MULTIMONITOR_EXPAND` | `'expand'` | Режим расширения рабочего стола (вместо клонирования `'mirror'`) |
| `KEYBOARD_MAP` / `XKEYBOARD` | `ru` / `"us,ru"` | Раскладки US/RU с переключением по `Alt + Shift` |
| `AUDIO_LEVEL` | `85` | Громкость звука по умолчанию |
| `USB_STORAGE_SYNC` | `on` | Автомонтирование и проброс флешек в удаленный рабочий стол |

> [!TIP]
> При необходимости настроить жестко заданную сеть Wi-Fi прямо в образе (чтобы ноутбуки подключались автоматически без ввода пароля пользователем), раскомментируйте в `thinstation.conf.buildtime`:
> ```bash
> WIRELESS_ESSID="Имя_Вашей_Сети"
> WIRELESS_WPAKEY="Пароль_От_Сети"
> ```

---

## 🛠️ Локальная сборка (Docker / WSL2)

Если необходимо собрать образ локально на компьютере под управлением Linux, WSL2 или Docker:

```bash
docker run --privileged --rm -v ${PWD}:/workspace fedora:42 /bin/bash -c "
  dnf install -y git dnf coreutils findutils procps-ng util-linux tar xz gzip dbus-tools which curl; dnf install -y --skip-broken linux-firmware wireless-regdb network-manager-applet iw || true
  chmod +x /workspace/scripts/build.sh
  /workspace/scripts/build.sh 7.2-Stable /workspace
"
```
Собранные ISO-образы сохраняются в каталоге `./output/`.
