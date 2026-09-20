# SkySecret
SkySecret (Sky Secret)

**A private workflow for secrets, files and SSH on Windows.**

[Русский](#русский) · [Download](https://github.com/Skyonave/sky_secret/releases) · [Security](SECURITY.md)

Local first, offline, one portable EXE. **Shift+Space → your vault → back to work.** SkySecret focuses on daily work with secrets; it is not intended as a KeePass replacement.

## Available now

- **Encrypted vaults:** passwords, notes, files, SSH and TOTP. Multiple vaults, folders and favorites.
- **Desktop controls:** compact tray window, search with **F**, right-click menus and **Ctrl+S** in editors.
- **Drag files both ways:** into the vault, or onto the desktop / File Explorer to export a copy. Exported copies are unencrypted.
- **Drag a secret into a field:** a small preview shows the entry name and what will be inserted. When a login/password pair is unambiguous in the same form or dialog, both fields are filled. Otherwise, a normal field receives the login and a masked field receives the password. Contents are replaced without using the clipboard; sign-in is not submitted. Requires compatible Windows accessibility fields. Press Esc to cancel.
- **Text editing:** create `.txt` files and edit text in separate windows.
- **Generator inside entries:** passwords, English passphrases, character rules and saved settings.
- **Backup and sync:** encrypted `.smv` import/export, local history, optional GitHub backups and manual synchronization with conflict review.
- **Quick actions:** copy secrets, use TOTP tiles and start saved SSH connections through Windows OpenSSH.

### Preview · synthetic data

| Vault workflow | Passwords and passphrases |
| --- | --- |
| ![Vault workflow](assets/previews/workflow.gif) | ![Generator](assets/previews/generator.gif) |

## Start

Download the EXE from **Releases**, run it, open the tray window and create a vault. **There is no master-password reset.** GitHub is optional. Keep verified independent backups.

Save edits before hiding: hiding locks the vault by default. Completed copies remain available for **10 seconds from copying**, including after hiding. Manual, idle and Windows locks clear the app's current copy immediately. Existing vaults remain readable; update all clients before saving a shared vault with a newer version.

> We work to protect your data, but cannot guarantee its security or recovery. [Protection and limits](SECURITY.md).

## General and Projects

Use **General / Projects** in the title bar. General remains a complete vault for everyday secrets; projects are optional. Existing vaults stay in General. Each general vault has its own project list.

- **Unlock with workspace:** unlock the general vault, then open a project without another password.
- **Separate master password:** enter the project's own password when opening it.
- Projects have independent encrypted files and data keys, history, export and synchronization. Locking a project keeps the workspace available; locking the workspace closes both. Idle and hide preferences apply to the whole workspace.
- Archive a project to hide it from the active list while retaining its file and access settings.

**Back up the general vault and each project separately.** A general-vault export includes the encrypted project catalog, but not project contents. Exporting a shared-unlock project asks for a password for that independent copy. To recover a missing project file, open its project and restore a `.smv` copy or select its GitHub backup. Existing files are not overwritten by restoration. Keep the workspace and export passwords separately; there is no password reset.

Next workflow: **Project → secrets → `.env` → run command**. Later: select the relevant project from context when opening **Shift+Space**. Windows Hello, hardware keys and session re-authentication are possible policy extensions, not implemented features or scheduled releases.

## Русский

**Приватный рабочий процесс для секретов, файлов и SSH на Windows.**

Локальные данные, работа без интернета, один переносимый EXE. **Shift+Space → сейф → нужное действие.** SkySecret развивается вокруг повседневной работы с секретами, а не как замена KeePass.

### Уже работает

- **Зашифрованные сейфы:** пароли, заметки, файлы, SSH и TOTP. Несколько сейфов, папки и избранное.
- **Desktop-интерфейс:** компактное окно у трея, поиск по **F**, контекстные меню и **Ctrl+S** в редакторах.
- **Перетаскивание в обе стороны:** добавление файлов в сейф и экспорт копии на рабочий стол или в Проводник. Внешняя копия не зашифрована.
- **Перетаскивание секрета в поле:** небольшая плашка показывает название записи и что будет вставлено. Если пара логин/пароль однозначно найдена в одной форме или диалоге, заполняются оба поля. Иначе обычное поле получает логин, скрытое — пароль. Содержимое заменяется без буфера обмена; кнопка входа не нажимается. Нужна поддержка заполнения через специальные возможности Windows. Esc отменяет жест.
- **Текстовые файлы:** создание `.txt` и редактирование текста в отдельных окнах.
- **Генератор в записи:** пароли, английские парольные фразы, выбор символов и сохранение настроек.
- **Копии и синхронизация:** импорт/экспорт `.smv`, локальная история, необязательный GitHub и ручная синхронизация с разбором конфликтов.
- **Быстрые действия:** копирование секретов, отдельные плашки TOTP и подключения через Windows OpenSSH.

### Начать

Скачайте EXE из **Releases**, запустите, откройте окно из трея и создайте сейф. **Сброса мастер-пароля нет.** GitHub подключается по желанию. Храните проверенные независимые копии.

Сохраняйте правки перед скрытием: по умолчанию оно блокирует сейф. Завершённое копирование доступно **10 секунд с момента копирования**, включая время после скрытия. Ручная блокировка, тайм-аут и блокировка Windows сразу очищают текущую копию приложения. Ранее созданные сейфы читаются; перед сохранением общего сейфа в новой версии обновляйте все устройства.

> Мы максимально стараемся обезопасить данные, но не можем гарантировать их безопасность и восстановление. [Защита и её границы](SECURITY.md).

### Общее и Проекты

Переключайтесь через **Общее / Проекты** в шапке. Общий сейф остаётся полноценным местом для повседневных секретов; проекты необязательны. Прежние сейфы остаются в «Общее». У каждого общего сейфа свой список проектов.

- **Открывать с workspace:** откройте общий сейф, затем проект без дополнительного пароля.
- **Отдельный мастер-пароль:** вводите собственный пароль проекта при его открытии.
- У проектов независимые зашифрованные файлы и ключи данных, история, экспорт и синхронизация. Блокировка проекта оставляет workspace открытым; блокировка workspace закрывает оба. Настройки тайм-аута и скрытия действуют на всё рабочее пространство.
- Архив скрывает проект из активного списка, сохраняя его файл и настройки доступа.

**Сохраняйте копии общего сейфа и каждого проекта отдельно.** Экспорт общего сейфа содержит зашифрованный каталог проектов, но не их содержимое. При экспорте проекта с общим открытием задаётся пароль независимой копии. Для восстановления отсутствующего файла откройте проект и выберите копию `.smv` или его резервную копию в GitHub. Восстановление не перезаписывает существующие файлы. Храните пароли workspace и экспортов отдельно; сброса пароля нет.

Следующий сценарий: **Проект → секреты → `.env` → запуск команды**. Затем — выбор проекта по контексту при вызове **Shift+Space**. Windows Hello, аппаратные ключи и повторное подтверждение сессии рассматриваются как расширения политики; они пока не реализованы и не имеют срока выпуска.

---

Passphrases: [EFF Long Wordlist](https://www.eff.org/dice), Joseph Bonneau / Electronic Frontier Foundation, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). [Attribution / источник](assets/wordlists/NOTICE.txt) · [License](LICENSE)
