# AtomVM_Zenoh — Claude Code 向けプロジェクトガイド

## プロジェクト概要

AtomVM のフォーク。M5Stack AtomS3 向けに M5Unified NIF を追加し、Gleam・Elixir で M5Stack デバイスを操作できるようにしたもの。

ターゲットボード: **M5Stack AtomS3 (ESP32-S3)**

---

## 環境セットアップ

### 必要ツール

| ツール | 用途 |
|---|---|
| mise | Erlang / Elixir / Gleam / rebar バージョン管理 |
| ESP-IDF v5.5.x | ESP32 ファームウェアビルド |
| esptool.py | フラッシュ書き込み |

### mise インストール・設定

```bash
curl https://mise.run | sh
# ~/.bashrc または ~/.zshrc に追記（mise の指示に従う）
```

プロジェクトルートの `mise.toml` にバージョンが定義済み：

```toml
[tools]
erlang = '27'
elixir = '1.17'
rebar = '3.27.0'
gleam = '1.17.0'
```

```bash
mise install
```

### ESP-IDF セットアップ

```bash
echo "deb [trusted=yes] https://dl.espressif.com/dl/eim/apt/ stable main" | sudo tee /etc/apt/sources.list.d/espressif.list
sudo apt update && sudo apt install eim-cli
eim install -i v5.5.4
alias getidf='source /home/hosoai/.espressif/tools/activate_idf_v5.5.4.sh'
```

### USB 権限（WSL）

```bash
sudo usermod -aG dialout $USER
```

usbipd で USB デバイスを WSL にアタッチしておく。

---

## AtomVM ビルド

### Unix ツール（PackBEAM など）

```bash
mkdir build && cd build
cmake ..
make -j8
sudo make install
```

### ESP32 VM（M5Unified NIF 込み）

```bash
cd src/platforms/esp32
getidf
idf.py set-target esp32s3
idf.py reconfigure   # 初回または sdkconfig 変更後
idf.py build
idf.py flash
idf.py monitor
```

---

## アプリのビルドとフラッシュ

### パーティション構成（重要）

| パーティション | オフセット | 用途 |
|---|---|---|
| factory | 0x10000 | AtomVM VM 本体 |
| boot.avm | 0x1D0000 | ブート AVM |
| **main.avm** | **0x250000** | **ユーザーアプリ** |

### Elixir アプリ

```bash
# プロジェクトルートの build ディレクトリで
make M5Blink

# フラッシュ（アドレスは必ず 0x250000）
esptool.py --chip esp32s3 --port /dev/ttyACM0 \
  write_flash 0x250000 build/examples/elixir/esp32/M5Blink.avm
```

### Gleam アプリ

```bash
cd examples/gleam/blink
gleam build
gleam export erlang-shipment

# AVM 作成
../../../build/tools/packbeam/PackBEAM blink.avm \
  build/erlang-shipment/blink/ebin/blink*.beam \
  build/erlang-shipment/gleam_stdlib/ebin/*.beam

# フラッシュ
esptool.py --chip esp32s3 --port /dev/ttyACM0 \
  write_flash 0x250000 blink.avm
```

---

## M5Unified NIF

### 実装場所

- **C++ ラッパー**: `src/platforms/esp32/components/avm_m5unified/m5unified_nif.cpp`
- **NIF 登録（C）**: `src/platforms/esp32/components/avm_m5unified/m5unified_reg.c`
- **Gleam バインディング**: `libs/gleam_avm/src/gleam_avm/m5.gleam`
- **Elixir ラッパー**: `libs/exavmlib/lib/M5.ex`

### 利用可能な NIF

| Erlang/NIF | Gleam | Elixir |
|---|---|---|
| `m5:begin/0` | `m5.begin()` | `M5.begin()` |
| `m5:update/0` | `m5.update()` | `M5.update()` |
| `m5:display_print/1` | `m5.display_print(text)` | `M5.display_print(text)` |
| `m5:display_println/1` | `m5.display_println(text)` | `M5.display_println(text)` |
| `m5:display_fill_screen/1` | `m5.display_fill_screen(color)` | `M5.display_fill_screen(color)` |
| `m5:display_set_cursor/2` | `m5.display_set_cursor(x, y)` | `M5.display_set_cursor(x, y)` |
| `m5:display_set_text_size/1` | `m5.display_set_text_size(size)` | `M5.display_set_text_size(size)` |
| `m5:display_set_text_color/1` | `m5.display_set_text_color(color)` | `M5.display_set_text_color(color)` |
| `m5:btn_a_is_pressed/0` | `m5.btn_a_is_pressed()` | `M5.btn_a_is_pressed()` |

色定数（RGB888 整数）: `black=0x000000`, `white=0xFFFFFF`, `red=0xFF0000` 等

---

## Zenoh NIF

### セットアップ（初回のみ）

zenoh-pico はサブモジュールとして `src/platforms/esp32/third_party/zenoh-pico/` に含まれる。

```bash
git submodule update --init --recursive
```

### 実装場所

- **NIF 実装**: `src/platforms/esp32/components/avm_zenoh/zenoh_nif.c`
- **Gleam バインディング**: `libs/gleam_avm/src/gleam_avm/zenoh.gleam`
- **Elixir ラッパー**: `libs/exavmlib/lib/Zenoh.ex`
- **Elixir サンプル**: `examples/elixir/esp32/ZenohPub.ex`, `ZenohSub.ex`

### 利用可能な NIF

| Erlang NIF | 説明 |
|---|---|
| `zenoh:open/1` | セッション開始 `open(<<"tcp/192.168.1.1:7447">>)` → `{ok, Session}` |
| `zenoh:close/1` | セッション終了 |
| `zenoh:put/3` | `put(Session, <<"key/expr">>, <<"payload">>)` → `ok` |
| `zenoh:declare_publisher/2` | `declare_publisher(Session, <<"key/expr">>)` → `{ok, Pub}` |
| `zenoh:publisher_put/2` | `publisher_put(Pub, <<"payload">>)` → `ok` |
| `zenoh:undeclare_publisher/1` | パブリッシャー解放 |
| `zenoh:declare_subscriber/2` | `declare_subscriber(Session, <<"key/**">>)` → `{ok, Sub}` |
| `zenoh:subscriber_recv/2` | `subscriber_recv(Sub, TimeoutMs)` → `{ok, KeyExpr, Payload}` \| `timeout` |
| `zenoh:undeclare_subscriber/1` | サブスクライバー解放 |

### 使用条件

- **WiFi 接続必須**: `zenoh:open/1` を呼ぶ前に AtomVM の `:network.start_link/1` でWiFi接続すること
- **Zenoh ルーター**: PC 側で `zenohd` を起動しておくこと
  ```bash
  docker run --network host eclipse/zenoh
  ```

### Elixir でのサンプル使用方法

```bash
# SSID・パスワード・ルーターアドレスを ZenohPub.ex / ZenohSub.ex に記入
make ZenohPub
esptool.py --chip esp32s3 --port /dev/ttyACM0 write_flash 0x250000 build/examples/elixir/esp32/ZenohPub.avm
```

---

## 既知の注意点

### I2C ドライバ競合
M5Unified（新 I2C API）と AtomVM（旧 I2C API）が共存するため `sdkconfig.defaults` に以下を設定済み：
```
CONFIG_I2C_SKIP_LEGACY_CONFLICT_CHECK=y
```
M5Unified の I2C ポートと AtomVM の `i2c:open()` で同じポートを同時使用しないこと。

### C++ NIF の注意
AtomVM の `term.h` は C++ モードで include 不可（`refc_binary_add_refcount` が `#ifndef __cplusplus`）。
NIF 実装は `.cpp`（M5Unified のみ）と `.c`（AtomVM ヘッダ + NIF 登録）に分離すること。

### フラッシュアドレス
ユーザーアプリは必ず `0x250000` に書き込む（`partitions.csv` の `main.avm` オフセット）。
`0x210000` は誤りで起動時 LoadProhibited クラッシュになる。
