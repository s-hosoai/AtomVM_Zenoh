# Zenoh NIF トラブルシューティング記録

AtomVM ESP32（M5Stack AtomS3）に zenoh-pico 1.9.0 の Pub/Sub NIF を追加した際に発生した問題と解決策の記録。

---

## ビルドエラー編

### 1. CMake パスエラー

**症状**: `zenoh-pico` のパス解決に失敗してビルドできない

**原因**: `CMakeLists.txt` で `CMAKE_CURRENT_SOURCE_DIR` / `CMAKE_SOURCE_DIR` を使っていたが、ESP-IDF の requirements フェーズではビルドディレクトリに解決されてしまう

**修正**: `COMPONENT_DIR` を使用する

```cmake
set(ZENOH_PICO_DIR "${COMPONENT_DIR}/../../third_party/zenoh-pico")
```

---

### 2. `driver/uart.h` not found

**症状**: `espidf.h` が `driver/uart.h` を include できない

**原因**: `idf_component_register` の `PRIV_REQUIRES` に `driver` が未記載

**修正**:
```cmake
PRIV_REQUIRES "libatomvm" "avm_sys" "esp_system" "driver" "lwip"
```

---

### 3. IPv6 型未定義エラー (`struct sockaddr_in6`)

**症状**: `network.c` で IPv6 関連の型が見つからない

**原因**: ESP-IDF は `CONFIG_LWIP_IPV6=n` の場合 IPv6 API を持たないが、zenoh-pico が UDP マルチキャスト（IPv6）を要求していた

**修正**: `ZENOH_GENERIC` カスタム設定で UDP マルチキャストを無効化

```c
// zenoh_config/zenoh_generic_config.h
#define Z_FEATURE_LINK_UDP_MULTICAST 0
#define Z_FEATURE_MULTICAST_TRANSPORT 1  // interest.c が無条件に呼ぶため残す
```

---

### 4. `_zp_multicast_send_join` 暗黙宣言警告

**症状**: `interest.c` でリンクエラー

**原因**: `interest.c` が `_zp_multicast_send_join` を feature flag なしに呼び出す

**修正**: `Z_FEATURE_MULTICAST_TRANSPORT 1` のままにして関数を有効化

---

### 5. `_z_raweth_*` 未定義参照

**症状**: リンク時に raweth 系関数が見つからない

**原因**: raweth ディレクトリを CMake で除外したが、呼び出し元コードは guard されていない

**修正**: `raweth/link.c`（stub あり）を追加 + `raweth_stubs.c` を手動作成

```c
// raweth_stubs.c - tx.c 側の 3 関数のスタブ
z_result_t _z_raweth_link_send_t_msg(...) { return _Z_ERR_TRANSPORT_NOT_AVAILABLE; }
z_result_t _z_raweth_send_t_msg(...)      { return _Z_ERR_TRANSPORT_NOT_AVAILABLE; }
z_result_t _z_raweth_send_n_msg(...)      { return _Z_ERR_TRANSPORT_NOT_AVAILABLE; }
```

---

### 6. factory パーティション容量超過

**症状**: `idf.py build` で "app partition too small" エラー

**原因**: M5Unified + Zenoh NIF でファームサイズが 4MB 想定の factory パーティションを超過

**修正**: `partitions.csv` を修正して factory を拡大、`sdkconfig.defaults` を 8MB に変更

```
factory,  app,  factory, 0x10000,  0x1C2000
boot.avm, data, phy,     0x1D2000,  0x7E000
main.avm, data, phy,     0x250000, 0x100000
```

```
# sdkconfig.defaults
CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
```

---

## ランタイムエラー編

### 7. WiFi 接続 API の誤り（`function_clause` クラッシュ）

**症状**: `network.start_link` で `function_clause` エラー

**原因**: Map `%{sta: %{}}` を渡していたが、AtomVM の `:network` モジュールは proplist `[sta: []]` を要求する

**修正**:
```elixir
{:ok, _} = :network.start_link(
  sta: [
    ssid: EspConfig.wifi_ssid(),
    psk: EspConfig.wifi_pass(),
    got_ip: fn _info -> send(parent, :got_ip) end,
    ...
  ]
)
receive do :got_ip -> :ok end
```

---

### 8. `Zenoh.open` 失敗（`zenoh_error`）— pthread_condattr 未実装

**症状**: WiFi 接続後に `Zenoh.open` が `zenoh_error` で失敗

**原因**: ESP-IDF の pthread は `pthread_condattr_setclock` を未実装（ENOSYS を返す）。condvar がデフォルト `CLOCK_REALTIME` のまま使われるが、`z_clock_now()` は `CLOCK_MONOTONIC` を使っており、`pthread_cond_timedwait` の abstime と基準クロックが不一致 → 全タイムアウトが即座に切れて `z_open()` 失敗

**修正**: `src/platforms/esp32/third_party/zenoh-pico/src/system/espidf/system.c` を修正

```c
// 修正前
pthread_condattr_t attr;
pthread_condattr_init(&attr);
pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
_Z_CHECK_SYS_ERR(pthread_cond_init(cv, &attr));

// 修正後（condattr を使わず CLOCK_REALTIME に統一）
_Z_CHECK_SYS_ERR(pthread_cond_init(cv, NULL));
```

あわせて `z_clock_now()` および elapsed 系関数の `CLOCK_MONOTONIC` を `CLOCK_REALTIME` に一括変更。

---

### 9. zenohd への TCP 接続失敗（RST/ACK が返る）

**症状**: TCP SYN は届くが zenohd から RST/ACK が返り接続不可

**原因 1 — Windows ファイアウォール**: Windows の個別ポートルールや app ルールが効かなかったのは、ネットワークプロファイル (Public/Private) と `BlockInboundAlways` の組み合わせ。Private プロファイルを無効化することで解決。

**原因 2 — zenohd が IPv6 only でリッスン**: 無引数起動の zenohd は `[::]:7447` (IPv6 wildcard) で listen。Windows はデフォルトで `IPV6_V6ONLY=1` のため、ESP32（IPv4）からの接続が拒否される。

**修正**:
```cmd
zenohd.exe -l tcp/0.0.0.0:7447
```

---

### 10. `publisher_put` 失敗（AtomVM GC によるセッション早期解放）

**症状**: session open・publisher declare は成功するが、最初の `publisher_put` で `zenoh_error`

**原因**: Elixir の tail-call recursive ループに入ると呼び出し元のスタックフレームが破棄され、`session` 変数への参照がなくなる。AtomVM の GC が `session` リソースを回収し `z_close()` を実行。`publisher_put` が closed session に対して実行される。

**修正**: `session` をループ引数として持ち回る

```elixir
# NG
loop(pub, 0)
defp loop(pub, count), do: ...; loop(pub, count + 1)

# OK
loop(session, pub, 0)
defp loop(session, pub, count), do: ...; loop(session, pub, count + 1)
```

ZenohSub.ex の `recv_loop(session, sub)` も同様に修正。

---

### 11. subscriber 受信時に Panic（Cache error / MMU entry fault）

**症状**: メッセージ受信のタイミングで `Guru Meditation Error: Cache error. MMU entry fault error` が発生し Core 0 のバックトレースが CORRUPTED になる

**原因**: `nif_zenoh_subscriber_recv` 内で `ZenohMessage msg`（keyexpr 256B + payload 4096B = 約 4360 バイト）をスタックに確保していた。AtomVM のスケジューラタスクのスタックが小さく、スタックオーバーフローが発生。return address が DRAM アドレスに上書きされ、リターン時に DRAM から命令実行しようとして MMU エラー。

**修正**: `nif_zenoh_subscriber_recv` の `ZenohMessage` をヒープ確保に変更

```c
// 修正前
ZenohMessage msg;
if (xQueueReceive(res->queue, &msg, ticks) != pdTRUE) { ... }

// 修正後
ZenohMessage *msg = malloc(sizeof(ZenohMessage));
if (IS_NULL_PTR(msg)) { RAISE_ERROR(OUT_OF_MEMORY_ATOM); }
if (xQueueReceive(res->queue, msg, ticks) != pdTRUE) {
    free(msg);
    return timeout_atom;
}
// ... 使用後 ...
free(msg);
```

subscriber callback (`zenoh_sub_callback`) も同様にヒープ確保に変更済み（read タスクのスタックは 20KB あるが統一のため）。

---

## まとめ

| # | 場所 | 問題 | 修正 |
|---|---|---|---|
| 1 | CMakeLists.txt | パス解決 | `COMPONENT_DIR` を使用 |
| 2 | CMakeLists.txt | driver 依存 | `PRIV_REQUIRES` に `driver` 追加 |
| 3 | zenoh_generic_config.h | IPv6 型未定義 | UDP マルチキャスト無効化 |
| 4 | zenoh_generic_config.h | multicast join | `MULTICAST_TRANSPORT` 有効化 |
| 5 | raweth_stubs.c | 未定義参照 | スタブ関数追加 |
| 6 | partitions.csv / sdkconfig | 容量超過 | 8MB / パーティション拡大 |
| 7 | ZenohPub.ex | WiFi API | proplist + `got_ip` callback |
| 8 | system.c (zenoh-pico) | pthread condattr | `CLOCK_REALTIME` に統一 |
| 9 | 環境 (Windows zenohd) | TCP 拒否 | `-l tcp/0.0.0.0:7447` で起動 |
| 10 | ZenohPub/Sub.ex | GC セッション解放 | `session` をループ引数で保持 |
| 11 | zenoh_nif.c | スタックオーバーフロー | `ZenohMessage` をヒープ確保 |
