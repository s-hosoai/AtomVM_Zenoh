# Getting Started

M5Stack AtomS3 (ESP32-S3) 向け AtomVM（M5Unified NIF + Zenoh NIF 入り）のセットアップ手順。

---

## 必要なもの

- Ubuntu / Debian 系 Linux（WSL2 可）
- mise
- ESP-IDF v5.5.4（eim でインストール）
- M5Stack AtomS3 ボード
- USB ケーブル（USB-C）

---

## 1. リポジトリのクローン

```bash
git clone git@github.com:s-hosoai/AtomVM_Zenoh.git
cd AtomVM_Zenoh
```

---

## 2. サブモジュール（zenoh-pico）のセットアップ

```bash
git submodule update --init --recursive
```

上記でファイルが展開されない場合は手動で checkout する：

```bash
cd src/platforms/esp32/third_party/zenoh-pico
git fetch origin
git checkout f266153e60224c21d05310e68f51a43f1b275f60
cd ../../../../..
```

---

## 3. mise のセットアップ

```bash
curl https://mise.run | sh
# 表示される指示に従い ~/.bashrc または ~/.zshrc に設定を追記
source ~/.bashrc   # または source ~/.zshrc

mise install
```

インストールされるバージョン（`mise.toml` で定義）：

| ツール | バージョン |
|--------|-----------|
| Erlang | 27 |
| Elixir | 1.17 |
| rebar  | 3.27.0 |
| Gleam  | 1.17.0 |

---

## 4. ESP-IDF のセットアップ

```bash
echo "deb [trusted=yes] https://dl.espressif.com/dl/eim/apt/ stable main" | sudo tee /etc/apt/sources.list.d/espressif.list
sudo apt update && sudo apt install eim-cli
eim install -i v5.5.4

# 以降のビルドで毎回実行するか ~/.bashrc に alias を追加
alias getidf='source /home/$USER/.espressif/tools/activate_idf_v5.5.4.sh'
```

### WSL2 の USB 権限

```bash
sudo usermod -aG dialout $USER
# ログアウト・再ログイン後に有効になる
```

usbipd で M5Stack AtomS3 の USB デバイスを WSL にアタッチしておく。

---

## 5. Unix ツールのビルド（PackBEAM など）

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
cd ..
```

> mise を有効化した状態（`mise activate` 済みのシェル）で実行すること。  
> rebar3 が見つからない場合は `eval "$(mise activate bash)"` を先に実行。

---

## 6. ESP32 ファームウェアのビルド

```bash
cd src/platforms/esp32
getidf   # ESP-IDF 環境を有効化
idf.py set-target esp32s3
idf.py build
cd ../../..
```

ビルド成功すると以下が生成される：

| ファイル | 用途 |
|---------|------|
| `src/platforms/esp32/build/bootloader/bootloader.bin` | ブートローダー |
| `src/platforms/esp32/build/partition_table/partition-table.bin` | パーティションテーブル |
| `src/platforms/esp32/build/atomvm-esp32.bin` | AtomVM 本体 |
| `build/libs/esp32boot/esp32boot.avm` | ブート AVM |

---

## 7. ファームウェアの書き込み

M5Stack AtomS3 を USB 接続した状態で：

```bash
cd src/platforms/esp32
idf.py flash
cd ../../..
```

または esptool.py で手動書き込み：

```bash
python -m esptool --chip esp32s3 -b 460800 \
  --before default_reset --after hard_reset \
  write_flash \
  --flash_mode dio --flash_size 4MB --flash_freq 80m \
  0x0      src/platforms/esp32/build/bootloader/bootloader.bin \
  0x8000   src/platforms/esp32/build/partition_table/partition-table.bin \
  0x10000  src/platforms/esp32/build/atomvm-esp32.bin \
  0x1d2000 build/libs/esp32boot/esp32boot.avm
```

書き込み後にシリアルモニタで起動確認：

```bash
cd src/platforms/esp32
idf.py monitor
```

---

## 8. アプリのビルドと書き込み

ユーザーアプリは必ず **`0x250000`** に書き込む。

### Elixir アプリ例（ZenohPub）

```bash
# examples/elixir/esp32/ZenohPub.ex の SSID・パスワード・ルーターアドレスを編集

# プロジェクトルートの build/ ディレクトリで実行（Unix ツールビルド済みであること）
cd build
make ZenohPub
cd ..

esptool.py --chip esp32s3 --port /dev/ttyACM0 \
  write_flash 0x250000 build/examples/elixir/esp32/ZenohPub.avm
```

### Gleam アプリ例（blink）

```bash
cd examples/gleam/blink
gleam build
gleam export erlang-shipment

../../../build/tools/packbeam/PackBEAM blink.avm \
  build/erlang-shipment/blink/ebin/blink*.beam \
  build/erlang-shipment/gleam_stdlib/ebin/*.beam

esptool.py --chip esp32s3 --port /dev/ttyACM0 \
  write_flash 0x250000 blink.avm
cd ../../..
```

---

## トラブルシューティング

### `git submodule update --init` でエラーが出る

zenoh-pico のコミットがパブリックに存在しない場合は「2. サブモジュールのセットアップ」の手動 checkout 手順を使う。

### `rebar3 is required` エラー

mise が PATH に入っていない。`eval "$(mise activate bash)"` を実行してから cmake を再実行。

### `idf.py: command not found`

ESP-IDF 環境が有効化されていない。`getidf`（`source ~/.espressif/tools/activate_idf_v5.5.4.sh`）を実行してから再試行。

### ビルドディレクトリが壊れている

```bash
rm -rf src/platforms/esp32/build
idf.py set-target esp32s3
idf.py build
```

### フラッシュ後に `LoadProhibited` でクラッシュする

アプリを `0x210000` に書いた可能性がある。正しいアドレスは **`0x250000`**。
