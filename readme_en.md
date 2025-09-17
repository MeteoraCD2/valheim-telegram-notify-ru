**Valheim Telegram Notify**

Valheim Telegram Notify is a simple bash script that monitors the Valheim server log file and sends notifications to a Telegram chat when it finds specific lines. It is designed for ease of use and should work on most Linux distributions.

**Supported Notifications**

The script recognizes 11 events that can be extracted from the Valheim server console log:

*   Player joined.
*   Player disconnected.
*   Character spawned.
*   Character died.
*   All online players went to sleep to skip the night, and a new day has begun.
*   A random event has started (see https://valheim.fandom.com/wiki/Events).
*   Server startup and world loading.
*   Server shutdown.
*   Low RAM.
*   Low disk space.
*   Server update required.

To disable notifications for a specific event, simply comment out the corresponding code block responsible for checking that event. Everything is commented for clarity.

**Preparation**

For Valheim to save a log file, you must add the `-logfile` parameter to your server startup script. Example:

`./valheim_server.x86_64 -name "My server" -port 2456 -world "Dedicated" -password "secret" -logfile "/valheim-server/logs/valheim_log.txt"`

**Prerequisites for Telegram**

You need to create a Telegram bot, add it to your chat, and obtain the chat's ID.

1.  Create a Telegram bot by following [these instructions](https://core.telegram.org/bots#6-botfather) and copy its API token.
2.  Add the bot to your Telegram chat.
3.  In your browser, open `https://api.telegram.org/bot<API-token>/getUpdates` and note the chat ID. Alternatively, you can find out the ID by sending your chat link to a bot like @username_to_id_bot.
4.  If your chat uses the forum (topics) format, you can find the topic ID in the topic header link. For example: https://t.me/chatname/1 - where `1` is the topic ID.

**Installation and Configuration**

1.  Place the `valheim-tg-notify.sh` and `messages.conf` files on your server, preferably in a dedicated directory, as the script will create a configuration file and a user list file upon its first run.
2.  Ensure that the user who will run the script has write permissions for the script's directory and read permissions for the Valheim log file.
3.  Grant execute permissions to the script: `chmod +x valheim-tg-notify.sh`.
4.  Run the script for the first time: `bash ./valheim-tg-notify.sh`. This will generate a settings file named `valheim-tg-notify.conf` in the same directory as the script.
5.  Fill in the settings in `valheim-tg-notify.conf`:
    *   `LOGFILE`: The full path to the Valheim server log file (the same file specified with the `-logfile` parameter).
    *   `KEY`: Your Telegram bot's API token.
    *   `CHATID`: The ID of the Telegram chat where the bot will send notifications.
    *   `THREAD_ID`: If the chat is a forum, specify the topic ID. Leave it empty for a regular chat.
6.  *(Optional)* The script now has a built-in function to fetch the player's Steam nickname using their SteamID. You no longer need to manually populate the `usernames.txt` file. However, you can still edit `usernames.txt` to customize names or add entries; the script will not overwrite existing data in this file.
7.  *(Optional)* You can edit the `messages.conf` file to customize the notification messages to your liking.

**Running the Script**

You can run the script directly with the command `bash ./valheim-tg-notify.sh`. However, the script will only run while the terminal session in which it was started remains open.

For automatic startup on system boot, you can create a systemd service:

1.  Create the service file: `sudo touch /etc/systemd/system/valheim-tg-notify.service`
2.  Add the following content to the created file:

    ```
    [Unit]
    Description=Telegram notification service for events on the Valheim server
    After=network.target
    Before=valheim.service

    [Service]
    Type=simple
    User=root
    WorkingDirectory=/path/to/your/script/directory
    ExecStart=/bin/bash /full/path/to/valheim-tg-notify.sh
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    ```

    *   Replace `root` with the username you want to run the service as. This user must have read access to the Valheim log file and write access to the script's directory.
    *   Replace `/path/to/your/script/directory` with the full path to the directory containing your script.
    *   Replace `/full/path/to/valheim-tg-notify.sh` with the full path to the `valheim-tg-notify.sh` script file.

**Steam Usernames**

Server log messages for player connections and disconnections reference the player's 64-bit Steam ID. The script will attempt to look up this Steam ID and store the ID along with the username in `usernames.txt`. If the script cannot find a matching Steam ID in `usernames.txt`, it will display `Unknown (Steam ID)` in the notification.

Messages regarding death and (re)spawning in the log mention the Valheim character name the player used to enter the world, so the script parses these names directly from the log.
