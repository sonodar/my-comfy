# boot

起動まわり一式。役割分担は以下のとおり。

- `cloud-init/`：初回起動時に失敗通知を先に設定し、S3 から起動用バンドルを取得して `install.sh` を呼ぶ。
- `install.sh`：初回セットアップ。パッケージ導入、ComfyUI 導入（版固定）、systemd ユニットの配置と有効化、起動まで。
- `systemd/`：起動のたびに動くユニット。インスタンスストアの初期化と S3 Files マウント（`mycomfy-init.service`）、ComfyUI 起動（`comfyui.service`）、自己チェック（`mycomfy-self-check.service`）。
  - cloud-init の user-data は停止→起動では再実行されないため、毎回必要な処理は必ずこちらに置く。
- `scripts/`：ユニットから呼ばれる実スクリプト（マウント、自己チェック、失敗通知）。

user-data が途中で失敗したときと、systemd がサービスの `OnFailure` を実行したときは、同じ通知スクリプトから notify-me の SNS トピックへ送る。自己チェックは成否どちらも SNS へ送る。

## マイルストーン 1（PoC）の範囲

「起動テンプレートから立てたインスタンスで、初期化が最後まで通って ComfyUI が動いている」まで。含むもの：エフェメラルディスクのマウント、S3 Files のマウントと POSIX 読み書き、ComfyUI サービスの起動、自己チェックと通知。含まないもの：モデルの同期、簡易 UI、Tailscale 参加。

PoC の制限：ComfyUI は版固定の git clone＋pip インストール（バンドル化は後で検討）。自己チェックの S3 可視確認だけは反映遅延のため警告扱い。

## エフェメラル（インスタンスストア）の判定設計

AMI によってデバイス名が変わるため、デバイス名を固定しない。

- **識別はハードウェア情報で行う**：`/dev/nvme*n1` を列挙し、`/sys/class/block/<dev>/device/model` に `Amazon EC2 NVMe Instance Storage` を含むデバイスが1台のときだけ処理を続ける。EBS は `Amazon Elastic Block Store` なので区別できる。`nvme1n1` のような番号の固定指定はしない（起動ごとに割り当てが変わりうる）。
- **DLAMI がマウント済みなら再利用する**：`/opt/dlami/nvme` がインスタンスストア上にあることを確かめ、`/mnt/instance-store` にバインドマウントする。
- **未初期化のデバイスだけフォーマットする**：単独のデバイスに既存のファイルシステムがあれば、そのまま `/mnt/instance-store` にマウントする。
- **検証してから使う**：デバイスが見つからない、または容量が想定未満なら sync ユニットを失敗させ、OnFailure の通知に乗せる。あわせて `nvidia-smi` で GPU が見えることも確認する（AMI のドライバが GPU 世代に非対応なら、ここで失敗として通知する）。
- 容量の検証は固定値ではなく `models/manifest.yaml` の合計サイズ＋余裕に対して行う。インスタンスストアが1台の構成では、この基準で容量を検証する。複数台の構成では検出時にエラーにする。
