#!/usr/bin/env python3
import sys, json, os, subprocess
from PyQt6.QtWidgets import *
from PyQt6.QtCore import *
from PyQt6.QtGui import *

APP_DIR = os.path.expanduser("~/.rovenchat")
ID_FILE = os.path.join(APP_DIR, "id.json")
INFO_FILE = os.path.join(APP_DIR, "info.json")
CONTACTS_FILE = os.path.join(APP_DIR, "contacts.json")

HUD_COLORS = {
    "Neon sinine": "#00c8ff",
    "Neon lilla": "#b400ff",
    "Neon roheline": "#00ff6a",
    "Neon roosa": "#ff2fd0",
    "Neon punane": "#ff1744",
}

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return default

class RovenChatGUI(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("RovenChat")
        self.resize(800, 500)

        self.current_color_name = "Neon sinine"

        main = QVBoxLayout(self)

        # Gamer Tag HUD
        hud_container = QHBoxLayout()
        main.addLayout(hud_container)

        self.hud_frame = QFrame()
        self.hud_frame.setObjectName("hudFrame")
        hud_layout = QVBoxLayout(self.hud_frame)
        hud_title = QLabel("Gamer Tag")
        hud_title.setObjectName("hudTitle")
        self.id_label = QLabel()
        self.ip_label = QLabel()
        hud_layout.addWidget(hud_title)
        hud_layout.addWidget(self.id_label)
        hud_layout.addWidget(self.ip_label)

        # HUD värvi nupp
        self.color_btn = QPushButton("HUD värv")
        self.color_btn.clicked.connect(self.change_hud_color_menu)
        hud_layout.addWidget(self.color_btn)

        hud_container.addWidget(self.hud_frame)
        hud_container.addStretch()

        # Põhialad
        center = QHBoxLayout()
        main.addLayout(center, 1)

        self.list = QListWidget()
        center.addWidget(self.list, 1)

        right = QVBoxLayout()
        center.addLayout(right, 2)

        self.chat = QTextEdit()
        self.chat.setReadOnly(True)
        right.addWidget(self.chat)

        self.input = QLineEdit()
        right.addWidget(self.input)

        send_btn = QPushButton("Saada")
        send_btn.clicked.connect(self.send_message)
        right.addWidget(send_btn)

        # Menüüriba
        bar = QMenuBar(self)
        friend_menu = bar.addMenu("Sõbrad")
        add_friend = friend_menu.addAction("Lisa sõber")
        add_friend.triggered.connect(self.add_friend_dialog)
        main.setMenuBar(bar)

        self.load_info()
        self.load_contacts()
        self.apply_hud_style()

    def load_info(self):
        id_data = load_json(ID_FILE, {})
        info_data = load_json(INFO_FILE, {})
        rid = id_data.get("id", "tundmatu")
        tip = info_data.get("tailscale_ip", "unknown")

        try:
            out = subprocess.check_output(["tailscale", "ip", "-4"], text=True).strip().splitlines()
            if out:
                tip = out[0]
        except:
            pass

        self.id_label.setText(f"ID: {rid}")
        self.ip_label.setText(f"Tailscale IP: {tip}")

    def load_contacts(self):
        self.list.clear()
        data = load_json(CONTACTS_FILE, {"friends": []})
        for f in data.get("friends", []):
            self.list.addItem(f"{f['name']} ({f['id']})")

    def add_friend_dialog(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("Lisa sõber")
        form = QFormLayout(dialog)

        name = QLineEdit()
        fid = QLineEdit()
        ip = QLineEdit()

        form.addRow("Nimi:", name)
        form.addRow("Sõbra ID:", fid)
        form.addRow("IP:", ip)

        btn = QPushButton("Lisa")
        form.addWidget(btn)

        def save():
            data = load_json(CONTACTS_FILE, {"friends": []})
            data.setdefault("friends", []).append({
                "name": name.text(),
                "id": fid.text(),
                "ip": ip.text()
            })
            with open(CONTACTS_FILE, "w") as f:
                json.dump(data, f, indent=4)
            self.load_contacts()
            dialog.close()

        btn.clicked.connect(save)
        dialog.exec()

    def send_message(self):
        item = self.list.currentItem()
        if not item:
            return
        friend_id = item.text().split("(")[1].split(")")[0]
        msg = self.input.text().strip()
        if not msg:
            return
        os.system(f"rovenchat-send {friend_id} \"{msg}\"")
        self.chat.append(f"Sina: {msg}")
        self.input.clear()

    def change_hud_color_menu(self):
        menu = QMenu(self)
        for name in HUD_COLORS.keys():
            menu.addAction(name)
        action = menu.exec(self.color_btn.mapToGlobal(self.color_btn.rect().bottomLeft()))
        if action:
            self.current_color_name = action.text()
            self.apply_hud_style()

    def apply_hud_style(self):
        color = HUD_COLORS.get(self.current_color_name, "#00c8ff")
        self.setStyleSheet(f"""
            QWidget {{
                background-color: #05060a;
                color: #e0e0ff;
                font-family: "Fira Sans", "Segoe UI", sans-serif;
            }}
            QListWidget {{
                background-color: #0b0d14;
                border: 1px solid #202233;
            }}
            QTextEdit {{
                background-color: #05060a;
                border: 1px solid #202233;
            }}
            QLineEdit {{
                background-color: #05060a;
                border: 1px solid #202233;
                padding: 4px;
            }}
            QPushButton {{
                background-color: #111322;
                border: 1px solid {color};
                padding: 6px 10px;
            }}
            QPushButton:hover {{
                background-color: #181b2e;
            }}
            QMenuBar {{
                background-color: #05060a;
            }}
            QMenu {{
                background-color: #05060a;
            }}
            QMenu::item:selected {{
                background-color: #181b2e;
            }}
            #hudFrame {{
                background-color: rgba(5, 6, 10, 220);
                border: 2px solid {color};
                border-radius: 8px;
            }}
            #hudTitle {{
                color: {color};
                font-weight: bold;
            }}
        """)

app = QApplication(sys.argv)
win = RovenChatGUI()
win.show()
app.exec()
