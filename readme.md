# Valheim Telegram Notify

Valheim Telegram Notify — это простой скрипт на bash, который проверяет log-файл сервера Valheim и отправляет уведомления в телеграм-чат, если находит нужные строки. Он создан для простоты использования и должен работать на большинстве дистрибутивов Linux.

## Поддерживаемые уведомления
Скрипт распознает 8 событий, которые можно извлечь из журнала консоли сервера:
1. Игрок присоединился.
2. Игрок отключился.
3. Игрок заспавнился.
4. Игрок умер.
5. Все игроки в сети легли спать, чтобы пропустить ночь, и начался новый день.
6. Запускается случайное событие, см. https://valheim.fandom.com/wiki/Events
7. Запуск сервера и загрузка мира.
8. Выключение сервера.
9. Недостаточно оперативной памяти.
10. недостаточно места на диске.

## Подготовка
### Чтобы Valheim сохранял файл лога, в скрипт запуска сервера нужно добавить параметр -logfile. Пример:  
`./valheim_server.x86_64 -name "My server" -port 2456 -world "Dedicated" -password "secret" -crossplay -logfile "/root/Valheim-server/logs/valheim_log.txt"`

### Предварительные требования для Telegram
Вам нужно создать телеграм-бота, добавить его в чат и получить ID этого чата.
- Создайте телеграм-бота, следуя [этим инструкциям](https://core.telegram.org/bots#6-botfather) и скопируйте API-токен
- Добавьте бота в чат в Telegram
- В браузере откройте страницу ``https://api.telegram.org/bot<API-token>/getUpdates`` и запомните ID чата

## Установка и настройка
- Разместите файлы **vh-tg-notify.sh** и **userlist.txt** на вашем сервере.
- В скрипте **vh-tg-notify.sh** настройте следующие переменные:
  - `CHATID`: ID телеграм-чата, куда бот будет отправлять уведомления.
  - `THREAD_ID`: Если чат имеет формат форума, то укажите ID темы. Если это обычный чат, оставьте пустым.
  - `KEY`: API-токен вашего телеграм-бота.
  - `LOGFILE`: Полный путь до файла лога сервера Valheim.
- Убедитесь, что **vh-tg-notify.sh** исполняемый, например, выполните ``chmod +x vh-tg-notify.sh``.
- Убедитесь, что пользователь, от имени которого будет запускаться скрипт, имеет доступ на запись в файл **userlist.txt**.
- ~~Добавьте 64-битные Steam ID с соответствующими именами пользователей в usernames.txt~~ Больше не требуется, скрипт попытается найти ID и имена пользователей. Однако, если вы хотите, вы можете изменить имена или добавить ID и имена, сам скрипт не перезапишет существующие данные в этом файле.

## Запуск
Вы можете просто запустить скрипт командой ``./vh-tg-notify.sh &``.  
Либо для автоматического запуска при загрузке системы можно создать systemd сервис:
   1. Создайте файл сервиса: `sudo touch /etc/systemd/system/vh-tg-notify.service`
   2. Добавьте в созданный файл следующее содержимое:
      ```
      [Unit]
      Description=Valheim Telegram Notification Service
      After=network.target
      Before=valheim.service

      [Service]
      Type=simple
      User=root
      ExecStart=/bin/bash /root/Valheim/valheim_tg_notify.sh
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
      ```
      - Вместо `root` введите имя пользователя, от имени которого хотите запускать сервис со скриптом. У этого пользователя, соответственно, должен быть доступ на чтение файла лога Valheim.

## Имена пользователей Steam
Сообщения о подключении и отключении в журнале сервера упоминают 64-битный Steam ID игрока, подключающегося к серверу. Скрипт попытается найти этот Steam ID и сохранит ID вместе с именем пользователя в usernames.txt. Если скрипт не найдет соответствующий Steam ID в usernames.txt, он сообщит ``Неизвестно (Steam ID)`` в уведомлении.
Сообщения о смерти и (пере)рождении в журнале упоминают имя персонажа Valheim, с которым игрок вошел в мир, поэтому скрипт непосредственно парсит их из журнала.
