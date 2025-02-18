import http.server
import socketserver
import os
import subprocess
import time
import threading

PORT = 1337
# Файл для приема команд от веб-интерфейса (его считывает mpv через Lua‑скрипт)
COMMAND_FILE = os.path.join(os.path.dirname(__file__), "mpv_cmd.txt")
CHECK_INTERVAL = 3  # Проверять MPV каждые 3 секунды

# HTML‑страница с плейсхолдерами для динамических опций аудио и субтитров
HTML_PAGE = """\
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MPV Remote</title>
    <style>
        /* Catppuccin Mocha Theme Colors */
        :root {
            --ctp-mocha-base: #1E1E2E;
            --ctp-mocha-surface0: #313244;
            --ctp-mocha-surface1: #45475A;
            --ctp-mocha-surface2: #585B70;
            --ctp-mocha-overlay: #6C7086;
            --ctp-mocha-text: #CDD6F4;
            --ctp-mocha-subtext0: #A6ADC8;
            --ctp-mocha-subtext1: #BAC2DE;
            --ctp-mocha-lavender: #B4BEFE;
            --ctp-mocha-blue: #89B4FA;
            --ctp-mocha-sapphire: #74C7EC;
            --ctp-mocha-sky: #89DCEB;
            --ctp-mocha-teal: #94E2D5;
            --ctp-mocha-green: #A6E3A1;
            --ctp-mocha-yellow: #F9E2AF;
            --ctp-mocha-peach: #FAB387;
            --ctp-mocha-maroon: #EBA0AC;
            --ctp-mocha-red: #F38BA8;
            --ctp-mocha-mauve: #CBA6F7;
            --ctp-mocha-pink: #F5C2E7;
            --ctp-mocha-flamingo: #FCA2AA;
        }

        body {
            font-family: Arial, sans-serif;
            text-align: center;
            margin: 0;
            padding: 20px;
            background-color: var(--ctp-mocha-base);
            color: var(--ctp-mocha-text);
        }

        h2 {
            color: var(--ctp-mocha-lavender);
        }

        button {
            position: relative;
            display: inline-block;
            padding: 15px 25px;
            margin: 10px;
            font-size: 16px;
            font-weight: bold;
            color: var(--ctp-mocha-text);
            background-color: var(--ctp-mocha-surface1);
            border: none;
            border-radius: 10px;
            box-shadow: 0 6px var(--ctp-mocha-surface2), 0 10px 15px rgba(0, 0, 0, 0.2);
            cursor: pointer;
            transition: all 0.1s ease;
            outline: none;
        }

        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px var(--ctp-mocha-surface2), 0 12px 20px rgba(0, 0, 0, 0.25);
        }

        button:active {
            transform: translateY(4px);
            box-shadow: 0 2px var(--ctp-mocha-surface2), 0 5px 10px rgba(0, 0, 0, 0.2);
        }

        select {
            padding: 10px;
            margin: 10px;
            font-size: 16px;
            border-radius: 5px;
            background-color: var(--ctp-mocha-surface1);
            color: var(--ctp-mocha-text);
            border: 1px solid var(--ctp-mocha-surface2);
        }

        label {
            font-size: 18px;
            color: var(--ctp-mocha-subtext0);
        }

        @media (max-width: 600px) {
            button {
                padding: 12px 20px;
                font-size: 14px;
            }

            select {
                padding: 8px;
                font-size: 14px;
            }

            label {
                font-size: 16px;
            }
        }
    </style>
</head>
<body>
    <h2>MPV Remote Control</h2>
    <button onclick="sendCommand('play')">▶ Play</button>
    <button onclick="sendCommand('pause')">⏸ Pause</button>
    <button onclick="sendCommand('stop')">⏹ Stop</button>
    <br>
    <button onclick="sendCommand('seek_forward')">⏩ +10 сек</button>
    <button onclick="sendCommand('seek_backward')">⏪ -10 сек</button>
    <br>
    <button onclick="sendCommand('volup')">🔊 Громкость +</button>
    <button onclick="sendCommand('voldown')">🔉 Громкость -</button>
    <br>
    <button onclick="sendCommand('fullscreen')">🔲 Fullscreen</button>
    <button onclick="sendCommand('sub_toggle')">📝 Subtitles</button>
    <br>
    <label for="audioTrack">Аудио:</label>
    <select id="audioTrack" onchange="sendTrackCommand('audio', this.value)">
        <!-- AUDIO_TRACKS -->
    </select>
    <br>
    <label for="subTrack">Субтитры:</label>
    <select id="subTrack" onchange="sendTrackCommand('sub', this.value)">
        <!-- SUB_TRACKS -->
    </select>
    <script>
        function sendCommand(cmd) {
            fetch("/" + cmd)
                .then(response => response.text())
                .then(data => console.log(data));
        }
        
        function sendTrackCommand(type, value) {
            fetch("/" + type + "_track_" + value)
                .then(response => response.text())
                .then(data => console.log(data));
        }
    </script>
</body>
</html>
"""

class MPVRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        """Обрабатываем входящие GET‑запросы"""
        command_map = {
            "/play": "set pause no",
            "/pause": "set pause yes",
            "/stop": "stop",
            "/volup": "add volume 5",
            "/voldown": "add volume -5",
            "/seek_forward": "seek 10",
            "/seek_backward": "seek -10",
            "/fullscreen": "cycle fullscreen",
            "/sub_toggle": "cycle sub",
        }

        if self.path == "/":
            # Читаем динамические опции для аудио и субтитров, сформированные Lua‑скриптом
            try:
                with open("mpv_tracks_audio.html", "r", encoding="utf-8") as f:
                    audio_options = f.read()
            except Exception:
                audio_options = '<option value="1">Дорожка 1</option><option value="2">Дорожка 2</option>'

            try:
                with open("mpv_tracks_sub.html", "r", encoding="utf-8") as f:
                    sub_options = f.read()
            except Exception:
                sub_options = ('<option value="no">Откл.</option>'
                               '<option value="1">Субтитры 1</option>'
                               '<option value="2">Субтитры 2</option>')

            html_page = HTML_PAGE.replace("<!-- AUDIO_TRACKS -->", audio_options)\
                                 .replace("<!-- SUB_TRACKS -->", sub_options)
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(html_page.encode("utf-8"))

        elif self.path in command_map:
            command = command_map[self.path]
            with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                f.write(command)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")

        elif self.path.startswith("/audio_track_"):
            # Обработка смены аудио дорожки
            track = self.path.split("_")[-1]
            with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                f.write(f"set audio {track}")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Audio track changed")

        elif self.path.startswith("/sub_track_"):
            # Обработка смены субтитров
            track = self.path.split("_")[-1]
            if track == "no":
                # При выборе "Откл." отправляем команду отключения субтитров
                sub_command = "set sid no"
            else:
                sub_command = f"set sid {track}"
            with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                f.write(sub_command)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Subtitle track changed")

        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")

def check_mpv_running():
    """Фоновый процесс, проверяющий, запущен ли MPV"""
    while True:
        time.sleep(CHECK_INTERVAL)
        try:
            result = subprocess.run('tasklist /FI "IMAGENAME eq mpv.exe"', capture_output=True, text=True, shell=True)
            if "mpv.exe" not in result.stdout:
                print("MPV закрыт. Завершаем сервер...")
                os._exit(0)
        except Exception as e:
            print("Ошибка при проверке MPV:", e)
            os._exit(0)

# Запускаем проверку MPV в отдельном потоке
threading.Thread(target=check_mpv_running, daemon=True).start()

# Запуск сервера
with socketserver.TCPServer(("", PORT), MPVRequestHandler) as httpd:
    print(f"HTTP сервер запущен на порту {PORT}")
    httpd.serve_forever()
