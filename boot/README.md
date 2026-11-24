# boot

起動まわり一式。役割分担は以下のとおり。

- `cloud-init/`：初回起動時だけ走る user-data（`user-data.sh`）。S3 から boot/ バンドルを取って `install.sh` を呼ぶだけの薄いもの。
- `install.sh`：初回セットアップ。パッケージ導入、ComfyUI 導入（版固定）、systemd ユニットの配置と有効化、起動まで。
- `systemd/`：起動のたびに動くユニット。インスタンスストアの初期化と S3 Files マウント（`mycomfy-init.service`）、ComfyUI 起動（`comfyui.service`）、自己チェック（`mycomfy-self-check.service`）。
  - cloud-init の user-data は停止→起動では再実行されないため、毎回必要な処理は必ずこちらに置く。
- `scripts/`：ユニットから呼ばれる実スクリプト（マウント、自己チェック、失敗通知）。

起動失敗時は systemd の OnFailure から `scripts/notify-failure.sh` を呼び、notify-me の SNS トピックへ publish する（LINE への配送は notify-me 側の責務）。自己チェックは成否どちらも SNS へ送る。

## マイルストーン 1（PoC）の範囲

「起動テンプレートから立てたインスタンスで、初期化が最後まで通って ComfyUI が動いている」まで。含むもの：エフェメラルディスクのマウント、S3 Files のマウントと POSIX 読み書き、ComfyUI サービスの起動、自己チェックと通知。含まないもの：モデルの同期、簡易 UI、Tailscale 参加。

PoC の制限：ComfyUI は版固定の git clone＋pip インストール（バンドル化は後で検討）。自己チェックの S3 可視確認だけは反映遅延のため警告扱い。

## エフェメラル（インスタンスストア）の判定設計

AMI によってデバイス名や既定マウント先が変わるため、パスを決め打ちしない。

- **識別はハードウェア情報で行う**：`/dev/nvme*n1` を列挙し、`/sys/class/block/<dev>/device/model` が `Amazon EC2 NVMe Instance Storage` のものをインスタンスストアとする。EBS は `Amazon Elastic Block Store` なので区別できる。`nvme1n1` のような番号の固定指定はしない（起動ごとに割り当てが変わりうる）。
- **マウント先は自分で決めた固定パス**（例：`/mnt/instance-store`）。AMI 側の慣習（`/media/ephemeral0` 等）には依存しない。
- **起動ごとに初期化する**：停止→起動で中身は消える前提の運用なので、sync ユニットが毎回フォーマットから冪等に作り直す。既存ファイルシステムの有無に左右されない。
- **検証してから使う**：デバイスが見つからない、または容量が想定未満なら sync ユニットを失敗させ、OnFailure の通知に乗せる。あわせて `nvidia-smi` で GPU が見えることも確認する（AMI のドライバが GPU 世代に非対応なら、ここで失敗として通知する）。
- 容量の検証は固定値ではなく `models/manifest.yaml` の合計サイズ＋余裕に対して行う。インスタンスタイプを変えてデバイス数や容量が変わっても、列挙＋検証で吸収する（現行の g6e.xlarge は 1 台 250GB。複数デバイスのタイプではストライプ化を足す）。
