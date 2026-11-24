# boot/cloud-init

初回起動時の user-data を置く。

やること：
- `/etc/mycomfy/env` に個人値（通知先 SNS、S3 Files ID、ComfyUI の版など）を落とす。
- user-data に埋め込んだ通知スクリプトと通知用 unit を配置する。バンドルの取得や展開、初回セットアップが失敗した場合は、notify-me の SNS トピックへ失敗箇所を送る。
- S3 から boot/ バンドル（`boot/mycomfy-boot.zip`）を取って展開し、`../install.sh` を呼ぶ。

user-data 自体は薄く保つ。実処理はバンドル内の `install.sh` と `systemd/`／`scripts/` が担う。モデル同期や ComfyUI 起動そのものは user-data では行わない（停止→起動で再実行されないため、per-boot の systemd 側の責務）。
