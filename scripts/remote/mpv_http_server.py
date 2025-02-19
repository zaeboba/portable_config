import http.server
import socketserver
import os
import subprocess
import time
import threading
from urllib.parse import urlparse, parse_qs

PORT = 1337
# Определяем папку, где находится этот скрипт
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
COMMAND_FILE = os.path.join(BASE_DIR, "mpv_cmd.txt")
CHECK_INTERVAL = 3  # Проверять MPV каждые 3 секунды
MAX_IDLE_TIME = 5  # Максимальное время без обновления файлов (в секундах)

HTML_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MPV Remote</title>
  <style>
    :root {
        --ctp-mocha-base: #1E1E2E;
        --ctp-mocha-surface0: #313244;
        --ctp-mocha-surface1: #45475A;
        --ctp-mocha-text: #CDD6F4;
        --ctp-mocha-subtext0: #A6ADC8;
        --ctp-mocha-lavender: #B4BEFE;
    }
    body {
        font-family: Arial, sans-serif;
        text-align: center;
        margin: 0;
        padding: 20px;
        background-color: var(--ctp-mocha-base);
        color: var(--ctp-mocha-text);
    }
    #currentFile {
        margin-bottom: 10px;
        font-size: 18px;
        font-weight: bold;
    }
    h2 {
        color: var(--ctp-mocha-lavender);
    }
    /* Группа кнопок Play, Pause, Stop – в один ряд, кнопки поменьше */
    .control-group-inline {
        display: flex;
        justify-content: center;
        gap: 5px;
        margin-bottom: 10px;
    }
    .small-button {
        padding: 10px 15px;
        font-size: 14px;
        color: var(--ctp-mocha-text);
        background-color: var(--ctp-mocha-surface1);
        border: none;
        border-radius: 10px;
        box-shadow: 0 6px var(--ctp-mocha-surface0), 0 10px 15px rgba(0, 0, 0, 0.2);
        cursor: pointer;
        transition: all 0.1s ease;
        outline: none;
    }
    .small-button:hover {
        transform: translateY(-2px);
        box-shadow: 0 8px var(--ctp-mocha-surface0), 0 12px 20px rgba(0, 0, 0, 0.25);
    }
    .small-button:active {
        transform: translateY(4px);
        box-shadow: 0 2px var(--ctp-mocha-surface0), 0 5px 10px rgba(0, 0, 0, 0.2);
    }
    /* Грид для остальных кнопок */
    .controls {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 10px;
        margin-bottom: 20px;
    }
    button {
        display: block;
        width: 100%;
        padding: 15px 25px;
        font-size: 16px;
        font-weight: bold;
        color: var(--ctp-mocha-text);
        background-color: var(--ctp-mocha-surface1);
        border: none;
        border-radius: 10px;
        box-shadow: 0 6px var(--ctp-mocha-surface0), 0 10px 15px rgba(0, 0, 0, 0.2);
        cursor: pointer;
        transition: all 0.1s ease;
        outline: none;
    }
    button:hover {
        transform: translateY(-2px);
        box-shadow: 0 8px var(--ctp-mocha-surface0), 0 12px 20px rgba(0, 0, 0, 0.25);
    }
    button:active {
        transform: translateY(4px);
        box-shadow: 0 2px var(--ctp-mocha-surface0), 0 5px 10px rgba(0, 0, 0, 0.2);
    }
    select,
    input[type="text"] {
        display: block;
        width: 90%;
        max-width: 400px;
        margin: 10px auto;
        padding: 10px;
        font-size: 16px;
        border-radius: 5px;
        background-color: var(--ctp-mocha-surface1);
        color: var(--ctp-mocha-text);
        border: none;
    }
    progress {
        width: 80%;
        height: 20px;
        margin: 10px auto;
        display: block;
        appearance: none;
        -webkit-appearance: none;
        background-color: var(--ctp-mocha-surface0);
        border-radius: 10px;
        overflow: hidden;
    }
    progress::-webkit-progress-bar {
        background-color: var(--ctp-mocha-surface0);
        border-radius: 10px;
    }
    progress::-webkit-progress-value {
        background-color: var(--ctp-mocha-lavender);
        border-radius: 10px;
    }
    progress::-moz-progress-bar {
        background-color: var(--ctp-mocha-lavender);
        border-radius: 10px;
    }
    progress::-ms-fill {
        background-color: var(--ctp-mocha-lavender);
        border-radius: 10px;
    }
    progress::-ms-thumb {
        background-color: var(--ctp-mocha-lavender);
        border-radius: 10px;
        width: 20px;
        height: 20px;
    }
    .modal {
        display: none;
        position: fixed;
        z-index: 1;
        left: 0;
        top: 0;
        width: 100%;
        height: 100%;
        background-color: rgba(0, 0, 0, 0.7);
    }
    .modal-content {
        background-color: var(--ctp-mocha-surface0);
        margin: 10% auto;
        padding: 20px;
        border: 1px solid var(--ctp-mocha-surface1);
        border-radius: 10px;
        width: 80%;
        max-height: 80%;
        overflow-y: auto;
    }
    .close {
        color: var(--ctp-mocha-text);
        float: right;
        font-size: 28px;
        font-weight: bold;
        cursor: pointer;
    }
    .close:hover,
    .close:focus {
        color: var(--ctp-mocha-lavender);
        text-decoration: none;
        cursor: pointer;
    }
    /* Обертка для блока с Аудио, Субтитрами, прогрессом и URL */
    .lower-section {
        margin-top: 30px;
    }
  </style>
</head>
<body>
    <div id="currentFile">Нет файла</div>
    <h2>MPV Remote Control</h2>
    
    <!-- Группа кнопок Play, Pause, Stop -->
    <div class="control-group-inline">
        <button class="small-button" onclick="sendCommand('play')">▶️ Play</button>
        <button class="small-button" onclick="sendCommand('pause')">⏸️ Pause</button>
        <button class="small-button" onclick="sendCommand('stop')">⏹️ Stop</button>
    </div>
    
    <!-- Остальные кнопки управления -->
    <div class="controls">
        <button onclick="sendCommand('seek_backward')">⏪ -10 сек</button>
        <button onclick="sendCommand('seek_forward')">⏩ +10 сек</button>
        <button onclick="sendCommand('voldown')">🔉 Громкость ➖</button>
        <button onclick="sendCommand('volup')">🔊 Громкость ➕</button>
        <button onclick="sendCommand('fullscreen')">🔲 Fullscreen</button>
        <button onclick="sendCommand('sub_toggle')">📝 Subtitles</button>
    </div>
    
    <!-- Кнопка Плейлист -->
    <button onclick="openPlaylistModal()">Плейлист 📜</button>
    
    <!-- Блок с элементами ниже, с дополнительным отступом сверху -->
    <div class="lower-section">
      <label for="audioTrack">Аудио:</label>
      <select id="audioTrack" onchange="sendTrackCommand('audio', this.value)">
          <!-- AUDIO_TRACKS -->
      </select>
      
      <label for="subTrack">Субтитры:</label>
      <select id="subTrack" onchange="sendTrackCommand('sub', this.value)">
          <!-- SUB_TRACKS -->
      </select>
      
      <progress id="progressBar" value="0" max="100"></progress>
      
      <!-- Блок для ввода URL -->
      <input type="text" id="urlInput" placeholder="Вставьте ссылку сюда...">
      <button onclick="sendLink()">Load URL</button>
    </div>

    <!-- Модальное окно для плейлиста -->
    <div id="playlistModal" class="modal">
        <div class="modal-content">
            <span class="close" onclick="closePlaylistModal()">&times;</span>
            <h2>Плейлист</h2>
            <ul id="playlistItems">
                <!-- PLAYLIST_ITEMS -->
            </ul>
        </div>
    </div>

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
        function sendLink() {
            const input = document.getElementById("urlInput");
            const url = input.value;
            if(url) {
                fetch("/load?url=" + encodeURIComponent(url))
                    .then(response => response.text())
                    .then(data => {
                        console.log(data);
                        input.value = ""; // Очищаем поле ввода после загрузки ссылки
                    });
            }
        }
        function updateCurrentFile() {
            fetch("/current_file")
                .then(response => response.text())
                .then(data => { document.getElementById("currentFile").textContent = data; });
        }
        setInterval(updateCurrentFile, 1000);
        function updateProgress() {
            fetch("/progress")
                .then(response => response.text())
                .then(data => {
                    const parts = data.split("/");
                    const current = parseFloat(parts[0]);
                    const total = parseFloat(parts[1]);
                    const progressBar = document.getElementById("progressBar");
                    if(total > 0) {
                        progressBar.value = (current / total) * 100;
                        progressBar.max = 100;
                    }
                });
        }
        setInterval(updateProgress, 1000);
        function seekToPosition() {
            const progressBar = document.getElementById("progressBar");
            const seekTime = progressBar.value / 100 * parseFloat(progressBar.max);
            fetch("/seek_to?time=" + encodeURIComponent(seekTime))
                .then(response => response.text())
                .then(data => console.log(data));
        }
        document.getElementById("progressBar").addEventListener("input", seekToPosition);
        function updatePlaylist() {
            fetch("/playlist")
                .then(response => response.text())
                .then(data => {
                    document.getElementById("playlistItems").innerHTML = data;
                });
        }
        setInterval(updatePlaylist, 1000);
        function openPlaylistModal() {
            document.getElementById("playlistModal").style.display = "block";
        }
        function closePlaylistModal() {
            document.getElementById("playlistModal").style.display = "none";
        }
        function playFile(index) {
            fetch("/play_file?index=" + encodeURIComponent(index))
                .then(response => response.text())
                .then(data => console.log(data));
        }
    </script>
</body>
</html>
"""

class MPVRequestHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        # Отключаем логирование HTTP-запросов
        pass

    def do_GET(self):
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
            try:
                with open(os.path.join(BASE_DIR, "mpv_tracks_audio.js"), "r", encoding="utf-8") as f:
                    audio_options = f.read()
            except Exception:
                audio_options = '<option value="1">Дорожка 1</option><option value="2">Дорожка 2</option>'
            try:
                with open(os.path.join(BASE_DIR, "mpv_tracks_sub.js"), "r", encoding="utf-8") as f:
                    sub_options = f.read()
            except Exception:
                sub_options = '<option value="no">Откл.</option><option value="1">Субтитры 1</option><option value="2">Субтитры 2</option>'
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
            track = self.path.split("_")[-1]
            with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                f.write(f"set audio {track}")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Audio track changed")
        elif self.path.startswith("/sub_track_"):
            track = self.path.split("_")[-1]
            if track == "no":
                sub_command = "set sid no"
            else:
                sub_command = f"set sid {track}"
            with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                f.write(sub_command)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Subtitle track changed")
        elif self.path == "/current_file":
            try:
                with open(os.path.join(BASE_DIR, "mpv_current_file.js"), "r", encoding="utf-8") as f:
                    data = f.read()
            except Exception:
                data = "Нет файла"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
        elif self.path == "/progress":
            try:
                with open(os.path.join(BASE_DIR, "mpv_progress.js"), "r", encoding="utf-8") as f:
                    data = f.read()
            except Exception:
                data = "0/0"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
        elif self.path == "/playlist":
            try:
                with open(os.path.join(BASE_DIR, "mpv_playlist.js"), "r", encoding="utf-8") as f:
                    data = f.read()
            except Exception:
                data = "<li>Плейлист пуст</li>"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
        elif self.path.startswith("/seek_to"):
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            if "time" in params:
                seek_time = params["time"][0]
                with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                    f.write(f"seek {seek_time} absolute")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Seeking to position")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad request")
        elif self.path.startswith("/load"):
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            if "url" in params:
                url = params["url"][0]
                with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                    f.write(f"loadfile {url}")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Loading file")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad request")
        elif self.path.startswith("/play_file"):
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            if "index" in params:
                index = params["index"][0]
                with open(COMMAND_FILE, "w", encoding="utf-8") as f:
                    f.write(f"set playlist-pos {index}")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Playing file from playlist")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad request")
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")

def check_mpv_running():
    last_update_time = time.time()
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

        # Проверяем временные файлы
        progress_file = os.path.join(BASE_DIR, "mpv_progress.js")
        current_file = os.path.join(BASE_DIR, "mpv_current_file.js")
        if os.path.exists(progress_file) and os.path.exists(current_file):
            last_update_time = time.time()
        elif time.time() - last_update_time > MAX_IDLE_TIME:
            print("Файлы не обновлялись более 5 секунд. Завершаем сервер...")
            os._exit(0)

threading.Thread(target=check_mpv_running, daemon=True).start()

try:
    with socketserver.TCPServer(("", PORT), MPVRequestHandler) as httpd:
        print(f"HTTP сервер запущен на порту {PORT}")
        httpd.serve_forever()
except KeyboardInterrupt:
    print("Сервер остановлен.")
except Exception as e:
    print(f"Неожиданная ошибка: {e}")